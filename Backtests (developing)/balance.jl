using DataFrames, Statistics

mutable struct Portfolio
    holdings::Dict{Int, Float64}  # Asset index → Number of units held
    cash::Float64                 # Cash balance
    last_value::Float64           # Portfolio value in previous iteration
    returns::Vector{Float64}      # List of portfolio returns
    first_run::Bool               # Track first iteration to prevent large returns

    function Portfolio(; initial_cash=10_000.0)
        return new(Dict{Int, Float64}(), initial_cash, 0.0, Float64[], true)
    end
end

function update_portfolio!(
    portfolio::Portfolio,
    buy_array::Vector{Int},
    sell_array::Vector{Int},
    bid_price_df::Vector{Float64},
    ask_price_df::Vector{Float64}
)
    # Buy assets (increase holdings, decrease cash)
    for buy_idx in buy_array
        buy_price = bid_price_df[buy_idx]
        cost = buy_price * 1.0  # Assume buying 1 unit per trade
        if portfolio.cash >= cost
            portfolio.cash -= cost
            portfolio.holdings[buy_idx] = get(portfolio.holdings, buy_idx, 0.0) + 1
        else
            println("Warning: Not enough cash to buy asset $buy_idx at price $buy_price")
        end
    end

    # Sell assets (decrease holdings, increase cash)
    for sell_idx in sell_array
        if get(portfolio.holdings, sell_idx, 0.0) > 0
            sell_price = ask_price_df[sell_idx]
            proceeds = sell_price * 1.0  # Assume selling 1 unit per trade
            portfolio.cash += proceeds
            portfolio.holdings[sell_idx] -= 1
        else
            println("Warning: Attempted to sell asset $sell_idx, but holdings are zero.")
        end
    end
end

function calculate_portfolio_value(portfolio::Portfolio, prices::Vector{Float64})
    if isempty(portfolio.holdings)
        return portfolio.cash  # If no holdings, portfolio value is just the cash
    end

    market_value = sum(((portfolio.holdings[i] * get(prices, i, 0.0)) for i in keys(portfolio.holdings)), init=0.0)
    return portfolio.cash + market_value
end

function calculate_portfolio_return!(portfolio::Portfolio, prices::Vector{Float64})
    if isempty(prices)
        println("Warning: Prices array is empty. Skipping return calculation.")
        return
    end

    current_value = calculate_portfolio_value(portfolio, prices)

    if portfolio.first_run
        println("Initializing portfolio at value: $current_value")
        portfolio.first_run = false
    else
        if portfolio.last_value == current_value
            println("No change in portfolio value. Return is 0.0.")
            push!(portfolio.returns, 0.0)  # Explicitly log zero return
        elseif portfolio.last_value > 0
            ret = (current_value - portfolio.last_value) / portfolio.last_value
            push!(portfolio.returns, ret)
        else
            println("Warning: last_value was zero or negative, skipping return calculation.")
        end
    end

    portfolio.last_value = current_value
end
