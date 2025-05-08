using Pkg, CSV, DataFrames, DynamicAxisWarping, Distances, Plots, NBInclude

#to pass first transaction_time available from each dataset
initial_time_df = []

#Read in asset-level prices
btcdf = CSV.read("Test Data\\btc_book-2024-08-01-trimmed.csv", DataFrame)
dgcdf = CSV.read("Test Data\\dgc_book-2024-08-01-trimmed.csv", DataFrame)
ethdf = CSV.read("Test Data\\eth_book-2024-08-01-trimmed.csv", DataFrame)
ltcdf = CSV.read("Test Data\\ltc_book-2024-08-01-trimmed.csv", DataFrame)

twoddf = [[btcdf] [dgcdf] [ethdf] [ltcdf]]

for (loop_index, df) in enumerate(twoddf)
     df = (select(df,[:"best_bid_price",:"best_ask_price",:"best_ask_qty",:"best_bid_qty",:"event_time", "transaction_time"]))
     push!(initial_time_df, first(df[!,"transaction_time"]))
     twoddf[loop_index] = df

     print("here first")

end

#constant to subtract from transaction_time column for each dataframe
subtract_time = minimum(initial_time_df)

loop_index = 1

for (loop_index, df) in enumerate(twoddf)

     df[!, :transaction_time] = df[!, :transaction_time] .- subtract_time
     sort!(df, :transaction_time)
     df = filter(row -> row.transaction_time < 172800000, df)
     df[!, "total_quantity"] = df[!,"best_ask_qty"]+ df[!,"best_bid_qty"]
     df[!, "weighted_avg_price"] = ((df[!,"best_ask_qty"].*df[!,"best_ask_price"]) + (df[!,"best_bid_qty"].*df[!,"best_bid_price"]))./df[!, "total_quantity"]
     
     #convert milliseconds to days
     transform!(df, :transaction_time => ByRow(x -> floor(Int, x / 86400000)) => :day_group)
     #group dataframe by day
     gdf = groupby(df, :day_group)
     #within each group, divide the price by the first price (being done daily now)
     transform!(gdf, :weighted_avg_price => (prices -> prices ./ first(prices)) => :price_index)

     twoddf[loop_index] = df

     print("here second")
end

@nbinclude("Models\\ILP\\TSP Pairs Trade Parameterized.ipynb")
@nbinclude("Models\\Similarity Factor & Bid-Ask Prices Parameterized.ipynb")
include("Models\\QUBO\\QUBO Pairs Trade Parameterized.jl")

level_2_df = []

for df in twoddf
     push!(level_2_df, filter(row -> row.transaction_time < 5000, df))
end

similarity = similarityfactor(level_2_df)

bid_price_df = []
ask_price_df = []

for df2 in level_2_df
     push!(bid_price_df, last(df2[!, "best_bid_price"]))
     push!(ask_price_df, last(df2[!, "best_ask_price"]))
end

@time begin
QUBO_Pairs_Trade(similarity, ask_price_df, bid_price_df, 6)
println("")
println("above is the QUBO result")
end

@time begin
display(TSP_Pairs_Trade(similarity, ask_price_df, bid_price_df, 15))
println("")
println("above is the ILP result")
end