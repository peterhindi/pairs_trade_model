include("data_read.jl")
mutable struct Account
     trade_size
     balance #initialize with starting balance  
     trades
       
     function Account(trade_size)
          new(trade_size, 0, [])
     end

end

function open_trade(account::Account,  model::Modelrun, window_df)
     trades = account.trades
     buy_position_size = model.buy_position_size
     sell_position_size = model.sell_position_size
     new_trades = push!(trades, model)
     account.trades = new_trades

     for asset in model.buy_array
          trade_size =  account.trade_size / (last(window_df[asset][!, "best_ask_price"]))
          push!(buy_position_size, trade_size)
     end

     for asset in model.sell_array
          trade_size = account.trade_size / (last(window_df[asset][!, "best_ask_price"]))
          push!(sell_position_size, trade_size)
     end

     model.buy_position_size = buy_position_size
     model.sell_position_size = sell_position_size

end

function close_trade(account::Account, model::Modelrun)
     trades = account.trades
     new_trades = filter!(e->e!=model, trades)
     account.trades = new_trades
end

function update_balance(account::Account, window_df)
     balance = account.balance
     
     if all(isempty,window_df) 
          println("No returns data in the timeline specified. Maintaining existing balance and moving to next iteration.")
     else
          for trade in account.trades
               for (i, asset) in enumerate(trade.buy_array)
                    balance += (last(window_df[asset][!, "best_bid_price"]) - first((window_df[asset][!, "best_ask_price"])))*trade.buy_position_size[i]
               end

               for (i, asset) in enumerate(trade.sell_array)
                    balance += (first(window_df[asset][!, "best_bid_price"]) - last((window_df[asset][!, "best_ask_price"]))) * trade.sell_position_size[i]
               end
          end
     end
     account.balance = balance
end

function trade_closing_logic_spread(account::Account, window_df)

     if isempty(account.trades)
          println("No trades opened at the current time period. No closings available")
     else
          #iterate through each open trade and update the spread for the current period
          for trade in account.trades
               if isempty(trade.pair) || all(isempty, window_df)
                    println("Trade has not been instantiated with a pair, or the dataframe is empty")
               else
                    sell_asset = trade.pair[1]
                    buy_asset = trade.pair[2]

                    #calculate the initial spread
                    initial_spread = first(window_df[sell_asset][!, "best_bid_price"]) - first(window_df[buy_asset][!, "best_ask_price"])
                    
                    #calculate the current spread at model run
                    current_spread = abs(last(window_df[trade.pair[1]][!, "best_bid_price"]) - last(window_df[trade.pair[2]][!, "best_ask_price"]))
                    
                    #if the spread decreased, close the trade
                    if current_spread < initial_spread
                         close_trade(account, trade)
                    end
               end
          end
     end
end

function trade_closing_logic_daily(account::Account, millisecond_tracker)
     if isempty(account.trades)
          println("No trades opened at the current time period. No closings available")
     else
          for trade in account.trades
               if isempty(trade.pair) || all(isempty, window_df)
                    println("Trade has not been instantiated with a pair, or the dataframe is empty")
               elseif trade.time_executed + 86400000 < millisecond_tracker
                    close_trade(account,trade)
               end
          end
     end
end