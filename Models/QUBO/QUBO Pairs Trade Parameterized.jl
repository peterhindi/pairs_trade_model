#Import packages
using Pkg, CSV, DataFrames, Statistics, Plots, Ipopt, Combinatorics, Distances, LinearAlgebra, AmplNLWriter, NBInclude, Gurobi, JuMP, Graphs, GraphRecipes#, PyCall

@nbinclude("..\\Similarity Factor & Bid-Ask Prices Parameterized.ipynb")
@nbinclude("..\\Cost Function Parameterized.ipynb")
@nbinclude("Penalty Function Parameterized.ipynb")

const env = Gurobi.Env()

#Compute forbidden subtours and return list of edges to forbid. Parameters are a list of components (in this case, cycles) for each callback solution, and a collection of callback edges.
function forbidden_tours(componentlist, cb_edges,null_index)
    print("null index is $null_index")
    #Initialize empty container to add subtour components
    component_container = []
    for component in componentlist
        println("below is component")
        display(component)
        #Indicator variable for component that includes null node; if null node is present, do not forbid. Otherwise, forbid the path.
        includes_null = 0
        #if the length of the component is one (if there is no edge/cycle), do not forbid
        if length(component) <= 1
            continue
        #if the length of a component is two (the cycle includes only two nodes such as 5 -> 3 -> 5), forbid it.
        elseif length(component) == 2
            push!(component_container, component)
            continue
        else
            #if the length of the component is greater than two and includes 5, this is an appropriate cycle that includes the null node. Do not forbid it.
            for elmt in component
                if elmt == null_index
                        includes_null = 1
                end
            end
        end
        #if the length of the component is greater than two and does not include the null node, then forbid it because it represents a subtour. Recall that we are also forbidding all cycles that have a length of two (2 edges)
        if includes_null != 1
            push!(component_container, component)
        end
        print("includes null value is $includes_null")
        display(componentlist)
    end
    
    #Initialize empty container to store forbidden edges in order of their component.
    edge_container = []
    #for forbidden components in the callback solution, compute the relevant edges for each component and add them to the edge_container.
    for component in component_container
        #for each component, initialize a container to store edges for the component.
        edge_set = []
        #for each element within the component, find the relevant edge by searching for the element within edge source nodes.
        for elmt in component
            for edge in cb_edges
                if src(edge) == elmt #|| dst(edge) == elmt
                        push!(edge_set,(src(edge),dst(edge)))
                end
            end
        end
        #push the edge set for the component to the broader container
        push!(edge_container, edge_set)
    end
    #Return the edge container
    return edge_container
end

#set tabu list length for moving window
tabu_list = [[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1],[1,1]]
tabu_index = 1


function tabu_list_push(soln_matrix,tabu_list,tabu_length)
    global tabu_index
    global tabu_list
    #push!(tabu_list, [col_num[1],row_num[1]])
    
    #dummy column
    index_max = size(soln_matrix)[1]

    #Find solution pair
    dummy_col = soln_matrix[index_max,:]
    dummy_row = soln_matrix[:,index_max]
    
    col_num = findall(dummy_col->dummy_col==1, dummy_col)
    row_num = findall(dummy_row->dummy_row==1, dummy_row)
    display(soln_matrix)
    #revolving index
    if (tabu_index <= tabu_length)
        tabu_list[tabu_index] = [col_num[1],row_num[1]]
        tabu_index += 1
    else
        tabu_list[1] = [col_num[1],row_num[1]]
        tabu_index = 2
    end
    return tabu_list
end

function QUBO_Pairs_Trade(similarity, ask_price_df, bid_price_df,tabu_length)
    
    global tabu_index
    global tabu_list
    global index_size_callback = size(similarity)[1] + 1

    #Initialize our model:
    pairs_trading_model = Model(() -> Gurobi.Optimizer(env))
    
    index_max = size(similarity)[1]
    
    #Set hyperparameters
    mc = 1
    mp = 100000000

    #Initialize our model:
    pairs_trading_model = Model(Gurobi.Optimizer)

    @variable(pairs_trading_model, x[i= 1:(index_max+1), j=1:(index_max+1)], Bin)
    @objective(pairs_trading_model, Min, costfunct(x, similarity, ask_price_df, bid_price_df)*mc + penaltyfunction(x, tabu_list)*mp)

    #@constraint(pairs_trading_model, tabulist[i in 1:size(tabu_list)[1]], x[(index_max+1),tabu_list[i][1]] + x[tabu_list[i][2],(index_max+1)] <= 1)

    #Lazy constraint to eliminate subtours and short cycles of length two from the solution when they arise.
    function subtour_elimination_callback(cb_data)
        status = callback_node_status(cb_data, pairs_trading_model)
        if status != MOI.CALLBACK_NODE_STATUS_INTEGER
            return  # Only run at integer solutions
        end
        
        #Convert callback solution in matrix form to a directed graph
        cb_graph = Graphs.DiGraph(callback_value.(cb_data, pairs_trading_model[:x]))
        #Assign a list of the graph components (in this case, cycles) to the componentlist variable
        componentlist = Graphs.strongly_connected_components(cb_graph)
        #Store edges of the directed graph in a collection variable cb_edges
        cb_edges = collect(Graphs.edges(cb_graph))
        #display(callback_value.(cb_data, pairs_trading_model[:x]))
        #print("This is a callback solution")
        #call the forbidden_tours function to locate forbidden cycles and return the relevant edges to forbid for each one
        edge_container = forbidden_tours(componentlist, cb_edges, index_size_callback)
        #If the function returns nothing, then do not initialize any lazy constraint
        if length(edge_container) == 0
            return
        else
            #display(edge_container)
            
            #For each forbidden cycle, build a lazy constraint to forbid the relevant edges by ensuring the sum of edges is less than the length of the component, effectively breaking the cycle.
            for term in edge_container
                edge_limit = length(term)
                #display(edge_limit)
                #display(term)
                con = @build_constraint(sum(pairs_trading_model[:x][edge[1], edge[2]] for edge in term) <= edge_limit-1)
                #display(con)
                MOI.submit(pairs_trading_model, MOI.LazyConstraint(cb_data), con)
            end
        end    
        return
    end

    set_attribute(
        pairs_trading_model,
        MOI.LazyConstraintCallback(),
        subtour_elimination_callback,
    )

    #Optimize model
    optimize!(pairs_trading_model)

    #Build solution matrix
    soln_matrix = round.(Int, value.(x))
    println("this is the soln_matrix below")
    display(soln_matrix)
    println("done printing soln matrix")

    #Add solution to tabu list
    tabu_list = tabu_list_push(soln_matrix,tabu_list,tabu_length)

    #display(Graphs.DiGraph(soln_matrix))
    #display(Graphs.strongly_connected_components(Graphs.DiGraph(soln_matrix)))
    #display(collect(Graphs.edges(Graphs.DiGraph(soln_matrix))))

    if objective_value(pairs_trading_model) >= 0
        return
    else
        return value.(x)
    end
end



#for each in tabu_list
   #@constraint( x[i,j] + x[z,i] <=1)

#lazy constraints
#save model redundancies