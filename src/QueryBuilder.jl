module QueryBuilder

import DataFrames, Tables
using Dates, TimeZones, Intervals
using SQLite, LibPQ

import PormG.Models: CharField, IntegerField
import PormG: Dialect
import PormG: config
import PormG: SQLType, SQLConn, SQLInstruction, SQLTypeF, SQLTypeOper, SQLTypeQ, SQLTypeQor, SQLObjectHandler, SQLObject, SQLTableAlias, SQLTypeText, SQLTypeOrder, SQLTypeField, SQLTypeArrays, PormGModel, PormGField, PormGTypeField
import PormG: PormGsuffix, PormGtrasnform
import PormG.Infiltrator: @infiltrate

#
# SQLTypeArrays Objects
#
@kwdef mutable struct SQLArrays <: SQLTypeArrays # TODO -- check if I need to use this
  count::Int64 = 1
  array_string::Array{String, 2} = Array{String, 2}(undef, 20, 3)
  array_int::Array{Int64, 2} = Array{Int64, 2}(undef, 20, 3)
end

#
# SQLInstruction Objects (instructions to build a query)
#
@kwdef mutable struct InstrucObject <: SQLInstruction
  text::String # text to be used in the query
  table_alias::SQLTableAlias
  alias::String
  object::SQLObject
  select::Vector{SQLTypeField} = Array{SQLTypeField, 1}(undef, 60)
  join::Vector{String} = []  # values to be used in join query
  _where::Vector{String} = []  # values to be used in where query
  agregate::Bool = false
  group::Vector{String} = []  # values to be used in group query
  having::Vector{String} = [] # values to be used in having query
  order::Vector{String} = [] # values to be used in order query  
  # df_join::Union{Missing, DataFrames.DataFrame} = missing # dataframe to be used in join query
  row_join::Vector{Dict{String, Any}} = [] # array of dictionary to be used in join query
  array_join::Array{String, 2} = Array{String, 2}(undef, 30, 8) # array to be used in join query (meaby the best way to do this)
  connection::Union{SQLite.DB, LibPQ.LibPQ.Connection, Nothing} = nothing
  array_defs::SQLTypeArrays = SQLArrays()
  cache::Dict{String, SQLTypeField} = Dict{String, SQLTypeField}()
  django::Union{Nothing, String} = nothing
end

# Store information to decide the name from table alias in subquery
mutable struct SQLTbAlias <: SQLTableAlias
  count::Int64
end
SQLTbAlias() = SQLTbAlias(0)
function get_alias(s::SQLTableAlias)
  if s.count == 0
    s.count += 1
    return "Tb"
  end
  s.count += 1
  return "R$(s.count -1)"
end

# Return a value to sql query, like value from DjangoSQLText
mutable struct SQLText <: SQLTypeText
  field::String
  _as::Union{String, Nothing}
end
SQLText(field::String; _as::Union{String, Nothing} = nothing) = SQLText(field, _as)
Base.copy(x::SQLTypeText) = SQLTypeText(x.field, x._as)


# Return a field to sql query
mutable struct SQLField <: SQLTypeField
  field::Union{SQLTypeText, SQLTypeF, String}
  _as::Union{String, Nothing}
end
SQLField(field::String; _as::Union{String, Nothing} = nothing) = SQLField(field, _as)
Base.copy(x::SQLTypeField) = SQLField(x.field, x._as)

# Return a order of field to sql query
mutable struct SQLOrder <: SQLTypeOrder
  field::Union{SQLTypeField, String}
  order::Union{Int64, Nothing}
  orientation::String
  _as::Union{String, Nothing}
end
SQLOrder(field::Union{SQLTypeField, String}; order::Union{Int64, Nothing} = nothing, orientation::String = "ASC", _as::Union{String, Nothing} = nothing) = SQLOrder(field, order, orientation, _as)
Base.copy(x::SQLTypeOrder) = SQLOrder(x.field, x.order, x.orientation, x._as)

#
# SQLObject Objects (main object to build a query)
#

mutable struct SQLObjectQuery <: SQLObject
  model::PormGModel
  values::Vector{Union{SQLTypeText, SQLTypeField}}
  filter::Vector{Union{SQLTypeQ, SQLTypeQor, SQLTypeOper}}
  insert::Dict{String, Any} # values to be used to create or insert
  limit::Int64
  offset::Int64
  order::Vector{SQLTypeOrder}
  group::Vector{String}
  having::Vector{String}
  list_joins::Vector{String} # is ther a better way to do this?
  row_join::Vector{Dict{String, Any}}  

  SQLObjectQuery(; model=nothing, values = [],  filter = [], insert = Dict(), limit = 0, offset = 0,
        order = [], group = [], having = [], list_joins = [], row_join = []) =
    new(model, values, filter, insert, limit, offset, order, group, having, list_joins, row_join)
end

#
# SQLTypeOper Objects (operators from sql)
#
export OP

"""
Mutable struct representing an SQL operator object for using in the filter and annotate.
That is a internal function, please do not use it.

# Fields
- `operator::String`: the operator used in the SQL query.
- `values::Union{String, Int64, Bool}`: the value(s) to be used with the operator.
- `column::Union{String, SQLTypeF}`: the column to be used with the operator.

"""
@kwdef mutable struct OperObject <: SQLTypeOper
  operator::String
  values::Union{String, Int64, Bool, SQLObjectHandler}
  column::Union{SQLTypeField, SQLTypeF, String, Vector{String}} # Vector{String} is need 
end
OP(column::String, value) = OperObject(operator = "=", values = value, column = SQLField(column))
OP(column::SQLTypeF, value) = OperObject(operator = "=", values = value, column = column)
OP(column::String, operator::String, value) = OperObject(operator = operator, values = value, column = SQLField(column))
OP(column::SQLTypeF, operator::String, value) = OperObject(operator = operator, values = value, column = column)

#
# SQLTypeQ and SQLTypeQor Objects
#

export Q, Qor

@kwdef mutable struct QObject <: SQLTypeQ
  filters::Vector{Union{SQLTypeOper, SQLTypeQ, SQLTypeQor}}
end

@kwdef mutable struct QorObject <: SQLTypeQor
  or::Vector{Union{SQLTypeOper, SQLTypeQ, SQLTypeQor}}
end

"""
  Q(x...)

  Create a `QObject` with the given filters.
  Ex.:
  ```julia
  a = object("tb_user")
  a.filter(Q("name" => "John", Qor("age" => 18, "age" => 19)))
  ```

  Arguments:
  - `x`: A list of key-value pairs or Qor(x...) or Q(x...) objects.

"""
function Q(x...)
  colect = [isa(v, Pair) ? _check_filter(v) : isa(v, Union{SQLTypeQor, SQLTypeQ, SQLTypeOper}) ? v : throw("Invalid argument: $(v); please use a pair (key => value)") for v in x]
  return QObject(filters = colect)
end


"""
  Qor(x...)

  Create a `QorObject` from the given arguments. The `QorObject` represents a disjunction of `SQLTypeQ` or `SQLTypeQor` objects.

  Ex.:
  ```julia
  a = object("tb_user")
  a.filter(Qor("name" => "John", Q("age__gte" => 18, "age__lte" => 19)))
  ```

  # Arguments
  - `x...`: A variable number of arguments. Each argument can be either a `SQLTypeQ` or `SQLTypeQor` object, or a `Pair` object.

"""
function Qor(x...)
  colect = [isa(v, Pair) ? _check_filter(v) : isa(v, Union{SQLTypeQor, SQLTypeQ, SQLTypeOper}) ? v : throw("Invalid argument: $(v); please use a pair (key => value)") for v in x]
  return QorObject(or = colect)
end

#
# SQLTypeF Objects (functions from sql)
#

export Sum, Avg, Count, Max, Min, When
@kwdef mutable struct FObject <: SQLTypeF
  function_name::String
  column::Union{String, SQLTypeField, N, Vector{N}, Vector{String}, SQLTypeOper, SQLTypeQ, SQLTypeQor, Vector{M}} where {N <: SQLTypeF, M <: SQLObject} # TODO Vector{M} is needed?
  agregate::Bool = false
  _as::Union{String, Nothing} = nothing
  kwargs::Dict{String, Any} = Dict{String, Any}()
end

function Sum(x; distinct::Bool = false)
  return FObject(function_name = "SUM", column = x, agregate = true, kwargs = Dict{String, Any}("distinct" => distinct))
end  
function Avg(x; distinct::Bool = false)
  return FObject(function_name = "AVG", column = x, agregate = true, kwargs = Dict{String, Any}("distinct" => distinct))
end
function Count(x; distinct::Bool = false)
  return FObject(function_name = "COUNT", column = x, agregate = true, kwargs = Dict{String, Any}("distinct" => distinct))
end
function Max(x)
  return FObject(function_name = "MAX", column = x, agregate = true)
end
function Min(x)
  return FObject(function_name = "MIN", column = x, agregate = true)
end
function Value(x::String)
  return SQLText(x)
end

function Cast(x::Union{String, SQLTypeText, SQLTypeF}, type::String)
  return FObject(function_name = "CAST", column = x, kwargs = Dict{String, Any}("type" => type))
end
function Cast(x::Union{String, SQLTypeText, SQLTypeF}, type::PormGField)
  return Cast(x, type.type)
end
function Concat(x::Union{Vector{String}, Vector{N}} where N <: SQLObject; output_field::Union{N, String, Nothing} where N <: PormGField = nothing, _as::String="")
  if isa(output_field, PormGField)
    output_field = output_field.type
  end
  return FObject(function_name = "CONCAT", column = x, kwargs = Dict{String, Any}("output_field" => output_field, "as" => _as))
end
function Extract(x::Union{String, SQLTypeF, Vector{String}}, part::String)
  return FObject(function_name = "EXTRACT", column = x, kwargs = Dict{String, Any}("part" => part))
end
function Extract(x::Union{String, SQLTypeF, Vector{String}}, part::String, format::String)
  return FObject(function_name = "EXTRACT", column = x, kwargs = Dict{String, Any}("part" => part, "format" => format))
end
function When(x::NTuple{N, Union{Pair{String, Int64}, Pair{String, String}}} where N; then::Union{String, Int64, Bool, SQLTypeF} = 0, _else::Union{String, Int64, Bool, SQLTypeF, Missing} = missing)
  return When(Q(x), then = then, _else = _else)
end
function  When(x::Union{Pair{String, Int64}, Pair{String, Int64}}; then::Union{String, Int64, Bool, SQLTypeF} = 0, _else::Union{String, Int64, Bool, SQLTypeF, Missing} = missing)
  return FObject(function_name = "WHEN", column = x |> _get_pair_to_oper, kwargs = Dict{String, Any}("then" => then, "else" => _else))
end
function When(x::Union{SQLTypeQ, SQLTypeQor}; then::Union{String, Int64, Bool, SQLTypeF} = 0, _else::Union{String, Int64, Bool, SQLTypeF, Missing} = missing)
  println(x |> typeof, x)
  return FObject(function_name = "WHEN", column = x, kwargs = Dict{String, Any}("then" => then, "else" => _else))
end
function Case(conditions::Vector{N} where N <: SQLTypeF; default::Any = "NULL", output_field::Union{N, String, Nothing} where N <: PormGField = nothing)
  if isa(output_field, PormGField)
    output_field = output_field.type
  end  
  return FObject(function_name = "CASE", column = conditions, kwargs = Dict{String, Any}("else" => default, "output_field" => output_field)) 
end
function Case(conditions::SQLTypeF; default::Any = "NULL", output_field::Union{N, String, Nothing} where N <: PormGField = nothing)
  if isa(output_field, PormGField)
    output_field = output_field.type
  end  
  return FObject(function_name = "CASE", column = conditions, kwargs = Dict{String, Any}("else" => default, "output_field" => output_field)) 
end
function To_char(x::Union{String, SQLTypeF, Vector{String}}, format::String)
  return FObject(function_name = "TO_CHAR", column = x, kwargs = Dict{String, Any}("format" => format))
end

MONTH(x) = Extract(x, "MONTH")
YEAR(x) = Extract(x, "YEAR")
DAY(x) = Extract(x, "DAY")
Y_M(x) = To_char(x, "YYYY-MM")
DATE(x) = To_char(x, "YYYY-MM-DD")
# Same that function CAST in django ORM
# # relatorio = relatorio.annotate(quarter=functions.Concat(functions.Cast(f'{data}__year', CharField()), Value('-Q'), Case(
# # 					When(**{ f'{data}__month__lte': 4 }, then=Value('1')),
# # 					When(**{ f'{data}__month__lte': 8 }, then=Value('2')),
# # 					When(**{ f'{data}__month__lte': 12 }, then=Value('3')),
# # 					output_field=CharField()
# # 				)))
QUARTER(x) = Concat([
                Cast(YEAR(x), CharField()), 
                Value("-Q"), 
                Case([When(OP(MONTH(x), "<=", 4), then = 1), 
                      When(OP(MONTH(x), "<=", 8), then = 2), 
                      When(OP(MONTH(x), "<=", 12), then = 3)
                      ], 
                      output_field = CharField())
                ], 
                output_field = CharField(), 
                _as = "$(x[1])__quarter")



function _get_pair_list_joins(q::SQLObject, v::Pair)
  push!(q.list_joins, v[1])
  unique!(q.list_joins)
end
function _get_pair_list_joins(q::SQLObject, v::SQLTypeQ)
  for v in v.filters
    _get_pair_list_joins(q, v)
  end
end
function _get_pair_list_joins(q::SQLObject, v::SQLTypeQor)
  for v in v.or
    _get_pair_list_joins(q, v)
  end
end

# ---
# Build the object
#

# Why Vector{String}
"Agora eu tenho que ver como que eu padronizo todas as variáveis para sair como SQLTypeField"
function up_values!(q::SQLObject, values::NTuple{N, Union{String, Symbol, SQLTypeF, SQLTypeText, SQLTypeField, Pair{String, T}}} where N where T <: SQLTypeF)
  # every call of values, reset the values
  q.values = []
  for v in values 
    isa(v, Symbol) && (v = String(v))
    if isa(v, SQLTypeText) || isa(v, SQLTypeField)
      push!(q.values, _check_function(v))
    elseif isa(v, SQLTypeF)
      push!(q.values, SQLField(_check_function(v), v._as))
    elseif isa(v, Pair) && isa(v.second, SQLTypeF)
      println(v.second)
      println(v.second |> typeof)
      push!(q.values, SQLField(_check_function(v.second), v.first))
    elseif isa(v, String)
      check = String.(split(v, "__@"))
      if size(check, 1) == 1
        push!(q.values, SQLField(v, v))
      elseif haskey(PormGsuffix, check[end])
        throw("Invalid argument: $(v) does not must contain operators (lte, gte, contains ...)")
      else    
        push!(q.values, SQLField(_check_function(check), join(check, "__")))
      end     
    else
      throw("Invalid argument: $(v) (::$(typeof(v)))); please use a string or a function (Mounth, Year, Day, Y_M ...)")
    end    
  end 
  
  return q
end
function up_values!(q::SQLObject, values)
  @error "Invalid argument: $(values) (::$(typeof(values))); please use a string or a function (Mounth, Year, Day, Y_M ...)"
end
  
function up_create!(q::SQLObject, values)
  q.insert = Dict()
  for (k,v) in values   
    q.insert[k] = v 
  end  

  return insert(q)
end

function up_update!(q::SQLObject, values::NTuple{N, Union{Pair{String, String}, Pair{String, Int64}}} where N)
  q.insert = Dict()
  for (k,v) in values   
    q.insert[k] = v 
  end  

  return update(q)
end

function up_filter!(q::SQLObject, filter)
  for v in filter   
    if isa(v, SQLTypeQ) || isa(v, SQLTypeQor) 
      push!(q.filter, v) # TODO I need process the Qor and Q with _check_filter
    elseif isa(v, Pair)
      push!(q.filter, _check_filter(v))
    else
      error("Invalid argument: $(v) (::$(typeof(v)))); please use a pair (key => value) or a Q(key => value...) or a Qor(key => value...)")
    end
  end
  return q
end

function _query_select(array::Vector{SQLTypeField})
  # println(typeof(array))
  # println(array)
  # println(size(array, 1))
  if !isassigned(array, 1, 1)
    return "*"
  else
    colect = []
    for i in 1:size(array, 1)     
      if !isassigned(array, i, 1)
        return join(colect,  ", \n  ")
      else
        push!(colect, "$(array[i, 1].field) as $(array[i, 1]._as)")
      end
    end
  end   
end

function order_by!(q::SQLObject, values::NTuple{N, Union{String, SQLTypeOrder}} where N)
  for v in values 
    if isa(v, String)
      # check if v constains - in the first position
      v[1:1] == "-" ? (orientation = "DESC"; v = v[2:end]) : orientation = "ASC"
      check = String.(split(v, "__@"))
      if size(check, 1) == 1
        push!(q.order, SQLOrder(SQLField(v, v), orientation=orientation))
      elseif haskey(PormGsuffix, check[end])
        throw("Invalid argument: $(v) does not must contain operators (lte, gte, contains ...)")
      else    
        push!(q.order, SQLOrder(SQLField(_check_function(check), join(check, "__")), orientation=orientation))
      end     
    else
      push!(q.order, v)
    end    
  end   
  return q  
end
function order_by!(q::SQLObject, values)
  throw("Invalid argument: $(values) (::$(typeof(values))); please use a string or a SQLTypeOrder)")
end
  
mutable struct ObjectHandler <: SQLObjectHandler
  object::SQLObject
  values::Function
  filter::Function
  create::Function
  update::Function
  order_by::Function

  # Constructor with keyword arguments
  function ObjectHandler(; object::SQLObject, 
                          values::Function = (x...) -> up_values!(object, x), 
                          filter::Function = (x...) -> up_filter!(object, x), 
                          create::Function = (x...) -> up_create!(object, x), 
                          update::Function = (x...) -> up_update!(object, x), 
                          order_by::Function = (x...) -> order_by!(object, x))
      return new(object, values, filter, create, update, order_by)
  end
end

export object

function object(model::PormGModel)
  return ObjectHandler(object = SQLObjectQuery(model = model))
end
# function object(model::String)
#   return object(getfield(Models, Symbol(model)))
# end
# function object(model::Symbol)
#   return object(getfield(Models, model))
# end
 
### string(q::SQLObjectQuery, m::Type{T}) where {T<:AbstractModel} = to_fetch_sql(m, q)

#
# Process the query entries to build the SQLObjectQuery object
#

# talvez eu não precise dessa função no inicio, mas pode ser útil na hora de processar o query
# function _check_function(f::OperObject)
function _check_function(f::Vector{N} where N <: SQLObject)
  r_v::Vector{SQLObject} = []
  for v in f
    if isa(v, SQLTypeOper)
      push!(r_v, _check_filter(v))
    else
      push!(r_v, _check_function(v))
    end
  end
  return r_v
end
function _check_function(f::FObject)
  f.column = _check_function(f.column)
  return f
end
function _check_function(f::SQLTypeOper)
  f.column = _check_function(f.column)
  return f
end
function _check_function(f::Union{SQLText, SQLField})
  return f
end
function _check_function(x::Vector{String})  
  if length(x) == 1
    return x[1]
  else    
    if haskey(PormGtrasnform, x[end])
      resp = getfield(@__MODULE__, Symbol(PormGtrasnform[x[end]]))(x[1:end-1])   
      return _check_function(resp)
    else
      joined_keys_with_prefix = join(map(key -> " \e[32m@" * key, keys(PormGtrasnform) |> collect), "\n")
      if haskey(PormGsuffix, x[end])
        yes = "you can use \"column__@\e[32m$(x[end])\e[0m\""
        not = "you can not use \"column__\e[31m@$(x[end])__@function\e[0m\". valid functions are:\n$(joined_keys_with_prefix)\e[0m"
        throw(ArgumentError("\e[4m\e[31m$(x[end])\e[0m is not allowed.\n$yes\n$not"))
      else
        throw(ArgumentError("\"$(x[1])__\e[31m@$(x[end])\e[0m\" is invalid; please use a valid function:\n$(joined_keys_with_prefix)\e[0m"))
      end
    end
  end    
end
_check_function(x::String) = _check_function(String.(split(x, "__@")))


"""
  _get_pair_to_oper(x::Pair)

  Converts a Pair object to an OperObject. If the Pair's key is a string, it checks if it contains an operator suffix (e.g. "__@gte", "__@lte") and returns an OperObject with the corresponding operator. If the key does not contain an operator suffix, it returns an OperObject with the "=" operator. If the key is not a string, it throws an error.

  ## Arguments
  - `x::Pair`: A Pair object to be converted to an OperObject.

  ## Returns
  - `OperObject`: An OperObject with the corresponding operator and values.

"""
function _get_pair_to_oper(x::Pair{Vector{String}, T}) where T <: Union{String, Int64, Bool}
  if haskey(PormGsuffix, x.first[end])
    return OperObject(operator = PormGsuffix[x.first[end]], values = x.second, column = SQLField(_check_function(x.first[1:end-1]), join(x.first[1:end-1], "__")))
  else    
    return OperObject(operator = "=", values = x.second, column = SQLField(_check_function(x.first), join(x.first, "__"))) # TODO, maybe I need to check if the column is valid and process the function before store
  end  
end
function _get_pair_to_oper(x::Pair{String, T}) where T <: Union{String, Int64, Bool}
  return _get_pair_to_oper(String.(split(x.first, "__@")) => x.second)
end
# Store SQLObject, to use __@in operator
function _get_pair_to_oper(x::Pair{Vector{String}, T}) where T <: SQLObjectHandler
  if x.first[end] == "in"
    return OperObject(operator = "in", values = x.second, column = SQLField(_check_function(x.first[1:end-1]), join(x.first[1:end-1], "__")))
  else
    throw("Invalid operator $(x.first[end]), only 'in' is allowed with a object")
  end

end
  

function _check_filter(x::Pair)
  # println(x)
  # println(typeof(x))
  if isa(x.first, String)
    check = String.(split(x.first, "__@"))
    return _get_pair_to_oper(check => x.second)  
  end
end


function _get_join_query(array::Vector{String}; array_store::Vector{String}=String[])
  # println(array)
  # println(array_store)
  array = copy(array)
  for i in 1: size(array, 1)
    # print(string(i, " - "))
    # print(array[i])
    # print(" ")
    for (k, value) in PormGsuffix
      if endswith(array[i], k)
        array[i] = array[i][1:end-length(k)]          
      end
    end
    for (k, value) in PormGtrasnform
      # print(endswith(array[i], k))
      if endswith(array[i], k)          
        array[i] = array[i][1:end-length(k)]  
        # print(" ")
        # print(array[i])
        # print(" ")        
      end
    end
    # println(array[i])
  end
  
  # how join to Vector
  # println(array)
  append!(array_store, array)
  unique!(array_store)
  # println(array_store)
  return array_store  
end

function _get_join_query(x::Tuple{Pair{String, Int64}, Vararg{Pair{String, Int64}}}; array_store::Vector{String} = String[])
  array = String[]
  for (k,v) in x
    push!(array, k)
  end
  _get_join_query(array, array_store=array_store)  
end
function _get_join_query(x::Tuple{String, Vararg{String}}; array_store::Vector{String} = String[])
  array = String[]
  for v in x
    push!(array, v)
  end
  _get_join_query(array, array_store=array_store)  
end
function _get_join_query(x::Dict{String,Union{Int64, String}}; array_store::Vector{String} = String[])
  array = String[]
  for (k,v) in x
    push!(array, k)
  end
  _get_join_query(array, array_store=array_store)  
end

function _get_alias_name(df::DataFrames.DataFrame, alias::String)
  array = vcat(df.alias_a, df.alias_b)
  count = 1
  while true
    alias_name = alias * string("_", count) # TODO maybe when exist more then one sql, the alias must be different
    if !in(alias_name, array)
      return alias_name
    end
    count += 1
  end
end
function _get_alias_name(row_join::Vector{Dict{String, Any}}, alias::String)
  array = vcat([r["alias_a"] for r in row_join], [r["alias_b"] for r in row_join])
  count = 1
  while true
    alias_name = alias * string("_", count) # TODO maybe when exist more then one sql, the alias must be different
    if !in(alias_name, array)
      return alias_name
    end
    count += 1
  end
end

function _insert_join(row_join::Vector{Dict{String, Any}}, row::Dict{String,String})
  # println(row_join)
  if size(row_join, 1) == 0
    push!(row_join, row)
    return row["alias_b"]
  else
    check = filter(r -> r["a"] == row["a"] && r["b"] == row["b"] && r["key_a"] == row["key_a"] && r["key_b"] == row["key_b"], row_join)
    if size(check, 1) == 0
      push!(row_join, row)
      return row["alias_b"]
    else
      if size(check, 1) > 1
        throw("Error in join")
      end
      return check[1]["alias_b"]  
    end
  end
end

"""
This function checks if the given `field` is a valid field in the provided `model`. If the field is valid, it returns the field name, potentially modified based on certain conditions.
"""
function _solve_field(field::String, model::PormGModel, instruct::SQLInstruction)
  # check if last_column a field from the model    
  # println(field)
  # println(model)
  if !(field in model.field_names)
    throw("Error in _build_row_join, the field $(field) not found in $(model.name): $(join(model.field_names, ", "))")
  end
  # println(model.fields[field] |> typeof)
  # println("---", hasfield(model.fields[field] |> typeof, :to))
  (instruct.django !== nothing && hasfield(model.fields[field] |> typeof, :to)) && (field = string(field, "_id"))
  # println(field)
  return field
end
_solve_field(field::String, _module::Module, model_name::Symbol, instruct::SQLInstruction) = _solve_field(field, getfield(_module, model_name), instruct) 
_solve_field(field::String, _module::Module, model_name::String, instruct::SQLInstruction) = _solve_field(field, _module, Symbol(model_name), instruct)
_solve_field(field::String, _module::Module, model_name::PormGModel, instruct::SQLInstruction) = _solve_field(field, model_name, instruct)

"build a row to join"
function _build_row_join(field::Vector{SubString{String}}, instruct::SQLInstruction; as::Bool=true)
  # convert the field to a vector of string
  vector = String.(field)
  _build_row_join(vector, instruct, as=as)  
end
function _build_row_join(field::Vector{String}, instruct::SQLInstruction; as::Bool=true)
  vector = copy(field) 
  println("_build_row_join")
  println(vector)
  foreign_table_name::Union{String, PormGModel, Nothing} = nothing
  foreing_table_module::Module = instruct.object.model._module::Module
  row_join = Dict{String,String}()
  # println(vector)

  # fields_model = instruct.object.model.field_names
  # println(fields_model)
  last_column::String = ""

  # println(instruct.object.model.reverse_fields)
  # println("fiels", instruct.object.model.fields)  
  # println("table", instruct.object.model.name)
  if vector[1] in instruct.object.model.field_names # vector moust be a field from the model
    last_column = vector[1]
    row_join["a"] = instruct.django !== nothing ? string(instruct.django, instruct.object.model.name |> lowercase) : instruct.object.model.name |> lowercase
    row_join["alias_a"] = instruct.alias
    how = instruct.object.model.fields[last_column].how
    if how === nothing
      row_join["how"] = instruct.object.model.fields[last_column].null == "YES" ? "LEFT" : "INNER"
    else
      row_join["how"] = how
    end
    foreign_table_name = instruct.object.model.fields[last_column].to
    if foreign_table_name === nothing
      throw("Error in _build_row_join, the column $(last_column) does not have a foreign key")
    elseif isa(foreign_table_name, PormGModel)
      row_join["b"] = instruct.django !== nothing ? string(instruct.django, foreign_table_name.name |> lowercase) : foreign_table_name.name |> lowercase
    else
      row_join["b"] = instruct.django !== nothing ? string(instruct.django,  foreign_table_name |> lowercase) : foreign_table_name |> lowercase
    end
    # row_join["alias_b"] = _get_alias_name(instruct.df_join) # TODO chage by row_join and test the speed
    row_join["alias_b"] = _get_alias_name(instruct.row_join, instruct.alias)
    row_join["key_b"] = instruct.object.model.fields[last_column].pk_field::String
    row_join["key_a"] = instruct.django !== nothing ? string(last_column, "_id") : last_column
  elseif haskey(instruct.object.model.reverse_fields, vector[1])
    reverse_model = getfield(foreing_table_module, instruct.object.model.reverse_fields[vector[1]][3])
    length(vector) == 1 && throw("Error in _build_row_join, the column $(vector[1]) is a reverse field, you must inform the column to be selected. Example: ...filter(\"$(vector[1])__column\")")
    # !(vector[2] in reverse_model.field_names) && throw("Error in _build_row_join, the column $(vector[2]) not found in $(reverse_model.name)")
    last_column = vector[2]
    row_join["a"] = instruct.django !== nothing ?  string(instruct.django, instruct.object.model.name |> lowercase) : instruct.object.model.name |> lowercase
    row_join["alias_a"] = instruct.alias
    how = reverse_model.fields[instruct.object.model.reverse_fields[vector[1]][1] |> String].how
    if how === nothing
      row_join["how"] = instruct.object.model.fields[instruct.object.model.reverse_fields[vector[1]][4] |> String].null == "YES" ? "LEFT" : "INNER"
    else
      row_join["how"] = how
    end
    foreign_table_name = instruct.object.model.reverse_fields[vector[1]][3] |> String
    if foreign_table_name === nothing
      throw("Error in _build_row_join, the column $(foreign_table_name) does not have a foreign key")
    elseif isa(foreign_table_name, PormGModel)
      row_join["b"] = instruct.django !== nothing ? string(instruct.django, foreign_table_name.name |> lowercase) : foreign_table_name.name |> lowercase
    else
      row_join["b"] = instruct.django !== nothing ? string(instruct.django,  foreign_table_name |> lowercase) : foreign_table_name |> lowercase
    end

    row_join["alias_b"] = _get_alias_name(instruct.row_join, instruct.alias)
    row_join["key_b"] = instruct.object.model.reverse_fields[vector[1]][1] |> String
    row_join["key_a"] = instruct.django !== nothing ? string(instruct.object.model.reverse_fields[vector[1]][4] |> String, "_id") : instruct.object.model.reverse_fields[vector[1]][4] |> String
  else
    throw("Error in _build_row_join, the column $(vector[1]) not found in $(instruct.object.model.name)")
  end
  
  # println(row_join)
  # println(instruct.row_join)
  vector = vector[2:end]  

  tb_alias = _insert_join(instruct.row_join, row_join)
  while size(vector, 1) > 1
    # println(foreign_table_name)
    # println(vector)
    row_join2 = Dict{String,String}()
    # get new object
    new_object = getfield(foreing_table_module, foreign_table_name |> Symbol)
    # println(new_object.reverse_fields)
    # println(new_object.field_names)

    if vector[1] in new_object.field_names
      !("to" in new_object.field_names) && throw("Error in _build_row_join, the column $(vector[1]) is a field from $(new_object.name), but this field has not a foreign key")
      # println(new_object.fields[vector[1]])
      last_column = vector[2]
      row_join2["a"] = row_join["b"]
      row_join2["alias_a"] = tb_alias
      how = new_object.fields[vector[1]].how
      if how === nothing
        row_join2["how"] = new_object.fields[vector[1]].null == "YES" ? "LEFT" : "INNER"
      else
        row_join2["how"] = how
      end
      foreign_table_name = new_object.fields[vector[1]].to
      if foreign_table_name === nothing
        throw("Error in _build_row_join, the column $(vector[2]) does not have a foreign key")
      elseif isa(foreign_table_name, PormGModel)
        row_join2["b"] = instruct.django !== nothing ? string(instruct.django, foreign_table_name.name |> lowercase) : foreign_table_name.name |> lowercase
      else
        row_join2["b"] = instruct.django !== nothing ? string(instruct.django,  foreign_table_name |> lowercase) : foreign_table_name |> lowercase
      end
      row_join2["alias_b"] = _get_alias_name(instruct.row_join, instruct.alias) # TODO chage by row_join and test the speed
      row_join2["key_b"] = new_object.fields[vector[1]].pk_field::String
      row_join2["key_a"] = instruct.django !== nothing ? string(vector[1], "_id") : vector[1]
      tb_alias = _insert_join(instruct.row_join, row_join2)
    
    elseif haskey(new_object.reverse_fields, vector[1])
      reverse_model = getfield(foreing_table_module, new_object.reverse_fields[vector[1]][3])
      length(vector) == 1 && throw("Error in _build_row_join, the column $(vector[1]) is a reverse field, you must inform the column to be selected. Example: ...filter(\"$(vector[1])__column\")")
      !(vector[2] in reverse_model.field_names) && throw("Error in _build_row_join, the column $(vector[2]) not found in $(reverse_model.name)")
      last_column = vector[2]
      row_join2["a"] = row_join["b"]
      row_join2["alias_a"] = tb_alias
      how = reverse_model.fields[new_object.reverse_fields[vector[1]][1] |> String].how
      if how === nothing
        row_join2["how"] = new_object.fields[new_object.reverse_fields[vector[1]][4] |> String].null == "YES" ? "LEFT" : "INNER"
      else
        row_join2["how"] = how
      end
      foreign_table_name = new_object.reverse_fields[vector[1]][3] |> String
      if foreign_table_name === nothing
        throw("Error in _build_row_join, the column $(foreign_table_name) does not have a foreign key")
      elseif isa(foreign_table_name, PormGModel)
        row_join2["b"] = instruct.django !== nothing ? string(instruct.django, foreign_table_name.name |> lowercase) : foreign_table_name.name |> lowercase
      else
        row_join2["b"] = instruct.django !== nothing ? string(instruct.django,  foreign_table_name |> lowercase) : foreign_table_name |> lowercase
      end

      row_join2["alias_b"] = _get_alias_name(instruct.row_join, instruct.alias)
      row_join2["key_b"] = new_object.reverse_fields[vector[1]][1] |> String
      row_join2["key_a"] = instruct.django !== nothing ? string(new_object.reverse_fields[vector[1]][4] |> String, "_id") : new_object.reverse_fields[vector[1]][4] |> String
      tb_alias = _insert_join(instruct.row_join, row_join2)
      vector = vector[2:end]

    else
      # println(field)
      throw("Error in _build_row_join, the column $(vector[1]) not found in $(new_object.name)")
    end
    vector = vector[2:end]
  end

  # tb_alias is the last table alias in the join ex. tb_1
  # last_column is the last column in the join ex. last_login
  # vector is the full path to the column ex. user__last_login__date (including functions (except the suffix))

  # functions must be processed here
  return string(tb_alias, ".", _solve_field(vector[end], foreing_table_module, foreign_table_name, instruct))
  
end

# outher functions
function _df_to_dic(df::DataFrames.DataFrame, column::String, filter::String)
  column = Symbol(column)
  loc = DataFrames.subset(df, DataFrames.AsTable([column]) => ( @. x -> x[column] == filtro) )
  if size(loc, 1) == 0
    throw("Error in _df_to_dic, $(filter) not found in $(column)")
  elseif size(loc, 1) > 1
    throw("Error in _df_to_dic, $(filter) found more than one time in $(column)")
  else 
    return loc[1, :]
  end
end

function ISNULL(v::String , value::Bool)
  if contains(v, "(")
    throw("Error in ISNULL, the column $(v) can't be a function")
  end
  if value
    return string(v, " IS NULL")
  else
    return string(v, " IS NOT NULL")
  end
end

# ---
# Build the SQLInstruction object
#

# select
function _get_select_query(v::SQLText, instruc::SQLInstruction)  
  # println("foi SQLText")
  return Dialect.VALUE(v.field, instruc.connection)
end

function _get_select_query(v::Vector{SQLObject}, instruc::SQLInstruction)
  # println("foi vector")
  resp = []
  for v in v
    push!(resp, _get_select_query(v, instruc))
  end
  return resp
end
# I think that is not the local to build the select query
function _get_select_query(v::String, instruc::SQLInstruction)
  # println("foi string")
  # println(v)
  # println(instruc.select)
  parts = split(v, "__")  
  if size(parts, 1) > 1
    return _build_row_join(parts, instruc)
  else
    return string(instruc.alias, ".", _solve_field(v, instruc.object.model, instruc))
  end 
  
end
function _get_select_query(v::SQLField, instruc::SQLInstruction)
  return _get_select_query(v.field, instruc)
end
function _get_select_query(v::SQLTypeOper, instruc::SQLInstruction)
  # println("foi SQLTypeOper")
  if isa(v.column, SQLTypeF) && haskey(v.column.function_name, PormGTypeField)
    value = getfield(Models, PormGTypeField[v.column.function_name])(v.values)
  else
    if isa(v.values, String)
      value = "'" * v.values * "'"
    else
      value = string(v.values)
    end
  end
  column = _get_select_query(v.column, instruc)
 
  if v.operator in ["=", ">", "<", ">=", "<=", "<>", "!="]   
    return string(column, " ", v.operator, " ", value)
  elseif v.operator in ["in", "not in"]
    return string(column, " ", v.operator, " (", join(value, ", "), ")")
  elseif v.operator in ["ISNULL"]
    return getfield(QueryBuilder, Symbol(v.operator))(column, v.values)
  else
    throw("Error in operator, $(v.operator) is not a valid operator")
  end
end
function _get_select_query(v::SQLTypeF, instruc::SQLInstruction)  
  # println("foi SQLTypeF")
  # println(v) 
  # println(v.kwargs)
  # println(v.function_name)
  # println(v.column |> typeof)
  value = getfield(Dialect, Symbol(v.function_name))(_get_select_query(v.column, instruc), v.kwargs, instruc.connection)
  # println(value)
  return value # getfield(Dialect, Symbol(v.function_name))(_get_select_query(v.column, instruc), v.kwargs, instruc.connection)
end

"""
  get_select_query(object::SQLObject, instruc::SQLInstruction)

  Iterates over the values of the object and generates the SELECT query for the given SQLInstruction object.

  #### ALERT
  - This internal function is called by the `build` function.

  #### Arguments
  - `object::SQLObject`: The object containing the values to be selected.
  - `instruc::SQLInstruction`: The SQLInstruction object to which the SELECT query will be added.
"""
function get_select_query(values::Vector{Union{SQLTypeText, SQLTypeField}}, instruc::SQLInstruction)
  for i in eachindex(values) # linear indexing
    v_copy = copy(values[i])
    if isa(v_copy.field, SQLTypeF) 
      if v_copy.field.agregate == false
        push!(instruc.group, i |> string)
      else 
        instruc.agregate = true
      end
    else
      push!(instruc.group, i |> string)
    end

    if haskey(instruc.cache, v_copy._as)
      instruc.select[i] = instruc.cache[v_copy._as]  # TODO That is necessary in get_select_query    
    else
      v_copy.field = _get_select_query(v_copy.field, instruc)
      instruc.select[i] = v_copy
      instruc.cache[v_copy._as] = instruc.select[i]
    end    
  end
end

function get_order_query(object::SQLObject, instruc::SQLInstruction)
  for v in object.order 
    found_in_select = false
    v_field_copy = copy(v.field)
    println(v_field_copy)
    if haskey(instruc.cache, v_field_copy._as)
      v_field_copy.field = instruc.cache[v_field_copy._as].field # TODO how can i recover the order of the field in select, maybe is better thar use the function in order by
    else
      v_field_copy.field = _get_select_query(v_field_copy.field, instruc)
    end     
    push!(instruc.order, string(v_field_copy.field, " ", v.orientation))
    instruc.cache[v_field_copy._as] = v_field_copy   

    # check if the field is in the select
    for value in object.values
      if isa(value, SQLTypeF) && value.field.agregate == true
        continue
      elseif value._as == v_field_copy._as
        found_in_select = true
        break
      end
    end

    if !found_in_select
      push!(instruc.group, v_field_copy.field)
    end

  end  
  return nothing  
end

function _get_filter_query(v::Vector{SubString{String}}, instruc::SQLInstruction, )
  # for loop from end to start exept the first
  v = String.(v)
  text = _build_row_join(v[1], instruc, as=false)
  i = 2
  to = size(v, 1)
  
  while i <= to
    function_name = functions[end]      
    text = getfield(Dialect, Symbol(PormGtrasnform[string(function_name)]))(text)
    functions = functions[1:end-1]
  end
end

# PAREI AQUI
function _get_filter_query(v::String, instruc::SQLInstruction)
  # V does not have be suffix
  contains(v, "@") && return _get_filter_query(split(v, "__@"), instruc)
  parts = split(v, "__")  
  if size(parts, 1) > 1
    return _build_row_join(parts, instruc, as=false)
  else
    return string(instruc.alias, ".", _solve_field(v, instruc.object.model, instruc))  
  end
  
end
# function _get_filter_query(v::SQLTypeF, instruc::SQLInstruction)
#   println("foi SQLTypeF")
#   return _get_select_query(v, instruc) 
# end
# function _get_filter_query(v::SQLTypeText, instruc::SQLInstruction)
#   println("foi SQLTypeText")
#   return _get_select_query(v, instruc)
# end
function _get_filter_query(v::SQLTypeField, instruc::SQLInstruction)
  # println("foi field3 SQLTypeField")
  # check if SQLTypeField exists in cache
  if haskey(instruc.cache, v._as)
    return instruc.cache[v._as].field
  else
    v_copy = copy(v)
    v_copy.field = _get_select_query(v_copy.field, instruc)
    instruc.cache[v_copy._as] = v_copy
    return v_copy.field
  end
end
function _get_filter_query(v::SQLTypeOper, instruc::SQLInstruction)
  println("foi SQLTypeOper")
  println(v)
  if isa(v.column, SQLTypeF) && haskey(v.column.function_name, PormGTypeField)
    value = getfield(Models, PormGTypeField[v.column.function_name])(v.values)
  elseif isa(v.values, SQLObjectHandler)
    if !(v.operator in ["in", "not in"])
      throw("Error in values, $(v.values) is not a SQLObjectHandler")
    end
    value = query(v.values, table_alias=instruc.table_alias, connection=instruc.connection)
    return string(_get_filter_query(v.column, instruc), " ", v.operator, " ($value)")
  else
    if isa(v.values, String)
      value = "'" * v.values * "'"
    else
      value = string(v.values)
    end
  end

  column = _get_filter_query(v.column, instruc)
  println(column)
  
  if v.operator in ["=", ">", "<", ">=", "<=", "<>", "!="]   
    return string(column, " ", v.operator, " ", value)
  elseif v.operator in ["in", "not in"]
    return string(column, " ", v.operator, " (", join(value, ", "), ")")
  elseif v.operator in ["ISNULL"]
    return getfield(QueryBuilder, Symbol(v.operator))(column, v.values)
  else
    throw("Error in operator, $(v.operator) is not a valid operator")
  end
end
function _get_filter_query(q::SQLTypeQ, instruc::SQLInstruction)
  # println("foi SQLTypeQ")
  resp = []
  for v in q.filters
    push!(resp, _get_filter_query(v, instruc))
  end
  return "(" * join(resp, " AND ") * ")"
end
function _get_filter_query(q::SQLTypeQor, instruc::SQLInstruction)
  resp = []
  for v in q.or
    push!(resp, _get_filter_query(v, instruc))
  end
  return "(" * join(resp, " OR ") * ")"
end


"""
  get_filter_query(object::SQLObject, instruc::SQLInstruction)

  Iterates over the filter of the object and generates the WHERE query for the given SQLInstruction object.

  #### ALERT
  - This internal function is called by the `build` function.

  #### Arguments
  - `object::SQLObject`: The object containing the filter to be selected.
  - `instruc::SQLInstruction`: The SQLInstruction object to which the WHERE query will be added.
"""
function get_filter_query(object::SQLObject, instruc::SQLInstruction)::Nothing 
  # println("get_filter_query")
  # [isa(v, Union{SQLTypeQor, SQLTypeQ, SQLTypeOper}) ? push!(instruc._where, _get_filter_query(v, instruc)) : throw("Error in values, $(v) is not a SQLTypeQor, SQLTypeQ or SQLTypeOper") for v in object.filter]
  for v in object.filter
    if isa(v, Union{SQLTypeQor, SQLTypeQ, SQLTypeOper})
      # println("Loc: ", _get_filter_query(v, instruc))
      push!(instruc._where, _get_filter_query(v, instruc))
    else
      throw("Error in values, $(v) is not a SQLTypeQor, SQLTypeQ or SQLTypeOper")
    end
  end  
  return nothing
end

function build_row_join_sql_text(instruc::SQLInstruction)
  # for row in eachrow(instruc.df_join)
  #   push!(instruc.join, """ $(row.how) JOIN $(row.b) $(row.alias_b) ON $(row.alias_a).$(row.key_a) = $(row.alias_b).$(row.key_b) """)
  # end
  # println(instruc.row_join)
  for value in instruc.row_join
    push!(instruc.join, """ $(value["how"]) JOIN $(value["b"]) $(value["alias_b"]) ON $(value["alias_a"]).$(value["key_a"]) = $(value["alias_b"]).$(value["key_b"]) """)
  end
end

function build(object::SQLObject; table_alias::Union{Nothing, SQLTableAlias} = nothing, connection::Union{Nothing, LibPQ.Connection, SQLite.DB} = nothing)
  # println(object.model.connect_key)
  settings = config[object.model.connect_key]
  connection === nothing && (connection = settings.connections) # TODO -- i need create a mode to handle with pools
  table_alias === nothing && (table_alias = SQLTbAlias())
  # println(connection)
  instruct = InstrucObject(text = "", 
    object = object,
    table_alias = table_alias === nothing ? SQLTbAlias() : table_alias,
    alias = get_alias(table_alias),
    connection = connection,
    django = settings.django_prefix
  )   

  # println(instruct)
  
  get_select_query(object.values, instruct)
  get_filter_query(object, instruct)
  build_row_join_sql_text(instruct)
  get_order_query(object, instruct)
  
  return instruct
end

# ---
# Pagination functions
#

export page

function page(object::SQLObjectHandler; limit::Int64 = 10, offset::Int64 = 0)
  object.object.limit = limit
  object.object.offset = offset
  return object
end
function page(object::SQLObjectHandler, limit::Int64)
  object.object.limit = limit
  return object
end
function page(object::SQLObjectHandler, limit::Int64, offset::Int64)
  object.object.limit = limit
  object.object.offset = offset
  return object
end

# ---
# Execute the query
#

export query

function query(q::SQLObjectHandler; table_alias::Union{Nothing, SQLTableAlias} = nothing, connection::Union{Nothing, LibPQ.Connection, SQLite.DB} = nothing) # TODO -- i need create a mode to change
  instruction = build(q.object, table_alias=table_alias, connection=connection) 
  # println(q.object)
  # println("$(instruction._where |> length > 0 ? "WHERE" : "")")
  respota = """
    SELECT
      $(_query_select(instruction.select ))
    FROM $(instruction.django !== nothing ? string(instruction.django, q.object.model.name |> lowercase) : q.object.model.name |> lowercase) as $(instruction.alias)
    $(join(instruction.join, "\n"))
    $(instruction._where |> length > 0 ? "WHERE" : "") $(join(instruction._where, " AND \n   "))
    $(instruction.agregate ? "GROUP BY $(join(instruction.group, ", ")) \n" : "") 
    $(instruction.order |> length > 0 ? "ORDER BY" : "") $(join(instruction.order, ", \n  "))
    $(q.object.limit !== 0 ? "LIMIT $(q.object.limit) \n" : "")
    $(q.object.offset !== 0 ? "OFFSET $(q.object.offset) \n" : "")
    """
  # @info respota
  return respota
end

function insert(objct::SQLObject; table_alias::Union{Nothing, SQLTableAlias} = nothing, connection::Union{Nothing, LibPQ.Connection, SQLite.DB} = nothing)
  model = objct.model
  settings = config[model.connect_key]
  connection === nothing && (connection = settings.connections) # TODO -- i need create a mode to handle with pools and create a function to this
  
  # colect name of the fields
  fields = model.field_names
  
  # check if is allowed to insert
  !settings.change_data && throw(ArgumentError("Error in insert, the connection \e[4m\e[31m$(model.connect_key)\e[0m not allowed to insert"))
  
  # check if the fields are in objct.insert
  for field in fields
    if !haskey(objct.insert, field)
      # check if field allow null or if exist a default value
      if model.fields[field].default !== nothing
        objct.insert[field] = model.fields[field].default
      elseif model.fields[field].type == "TIMESTAMPTZ" && (model.fields[field].auto_now_add || model.fields[field].auto_now)
        objct.insert[field] = model.fields[field].formater(now(), settings.time_zone)
      elseif model.fields[field].type == "DATE" && (model.fields[field].auto_now_add || model.fields[field].auto_now)
        objct.insert[field] = model.fields[field].formater(today())
      elseif model.fields[field].null || model.fields[field].primary_key
        continue
      else
        @infiltrate
        throw(ArgumentError("Error in insert, the field \e[4m\e[31m$(field)\e[0m not allow null"))
      end
    end
  end

  pk_exist::Bool = false
  pk_field::Vector{String} = []
  for field in keys(objct.insert)
    # check if the insert has a field that not exist in the model
    in(field, fields) || throw("""Error in insert, the field "$(field)" not found in $(model.name)""")
    # check if the field is a primary key
    model.fields[field].primary_key && (pk_exist = true; push!(pk_field, field))
    # check if the field has max_length and validate
    hasfield(typeof(model.fields[field]), :max_length) && length(objct.insert[field]) > model.fields[field].max_length && error("""Error in insert, the field \e[4m\e[31m$(field)\e[0m has a max_length of \e[4m\e[32m$(model.fields[field].max_length)\e[0m, but the value has \e[4m\e[31m$(length(objct.create[field]))\e[0m""")
    # check if the field has max_digits and validate
    if hasfield(typeof(model.fields[field]), :max_digits)
      value_str = string(objct.insert[field])
      integer_part, fractional_part = split(value_str, ".")
      total_digits = length(replace(integer_part, "-" => "")) + length(fractional_part)
      if total_digits > model.fields[field].max_digits
        error("""Error in insert, the field \e[4m\e[31m$(field)\e[0m has a max_digits of \e[4m\e[32m$(model.fields[field].max_digits)\e[0m, but the value has \e[4m\e[31m$(total_digits)\e[0m""")
      end
    end
  end

  # insert
  fields_columns = join([field for field in keys(objct.insert)], ", ")

  # values
  values_insert = join([objct.insert[field] |> model.fields[field].formater for field in keys(objct.insert)], ", ")

  # TODO: insert a function to handle with the different types of connection and modulate the code

  # construct the SQL statement
  sql = """
  INSERT INTO $(string(model.name)) (
    $(fields_columns)
  ) VALUES (
    $(values_insert)
  )
  """

  # @info sql

  # execute the SQL statement
  if connection isa LibPQ.Connection
    result = LibPQ.execute(connection, sql * " RETURNING *;")
  elseif connection isa SQLite.DB
    SQLite.execute(connection, sql)
    # Assuming the table has an auto-increment primary key named "id"
    last_id = SQLite.last_insert_rowid(connection)
    result = SQLite.Query(connection, "SELECT * FROM $(string(model.name)) WHERE id = $last_id;")
  else
    throw("Unsupported connection type")
  end

  pk_exist && _update_sequence(model, connection, pk_field)

  return Tables.rowtable(result) |> first |> x -> Dict(Symbol(k) => v for (k, v) in pairs(x))

end

function _update_sequence(model::PormGModel, connection::LibPQ.Connection, pk_field::Vector{String})
  for field in pk_field
    try
      LibPQ.execute(connection, "SELECT setval('$(string(model.name |> lowercase))_$(field)_seq', (SELECT MAX($(field)) + 1 FROM $(string(model.name |> lowercase))), true);")
    catch e
      @infiltrate
      if occursin("does not exist", e |> string)        
        _fix_sequence_name(connection, model)
        LibPQ.execute(connection, "SELECT setval('$(string(model.name |> lowercase))_$(field)_seq', (SELECT MAX($(field)) + 1 FROM $(string(model.name |> lowercase))), true);")
      end
    end
  end
end

function _fix_sequence_name(connection::LibPQ.Connection, model::PormGModel) # TODO maby i need use Migration get_sequence_name aproach
  pk_field = [field for field in keys(model.fields) if model.fields[field].primary_key]
  sequences = LibPQ.execute(connection, """SELECT *
      FROM pg_sequences
      WHERE sequencename LIKE '$(model.name |> lowercase)%';""") |> DataFrames.DataFrame  
  for (index, row) in enumerate(eachrow(sequences))
    if index == 1 && row.sequencename != "$(model.name |> lowercase)_$(pk_field[1])_seq"
      if length(pk_field) == 0
        throw("Error in _fix_sequence_name, the model $(model.name) does not have a primary key")
      elseif length(pk_field) > 1
        throw("Error in _fix_sequence_name, the model $(model.name) has more than one primary key")
      end
      LibPQ.execute(connection, "ALTER SEQUENCE $(row.sequencename) RENAME TO $(model.name |> lowercase)_$(pk_field[1])_seq;")
    else
      LibPQ.execute(connection, "DROP SEQUENCE $(row.sequencename);")
    end
  end
end

# function _update_sequence(model::PormGModel, connection::LibPQ.Connection, pk_field::Vector{String})
#   sequences = LibPQ.execute(connection, """SELECT *
#       FROM pg_sequences
#       WHERE sequencename LIKE '$(model.name |> lowercase)%';""") |> DataFrames.DataFrame
#   for row in eachrow(sequences)
#     if row.sequenceowner == model.name
#       LibPQ.execute(connection, "SELECT setval('$(row.sequencename)', (SELECT MAX($(pk_field[1])) FROM $(model.name)), true);")
#     end
#   end
# end
function _update_sequence(model::PormGModel, connection::SQLite.DB, pk_field::Vector{String})
  for field in pk_field
    max_id_query = "SELECT MAX($(field)) FROM $(string(model.name |> lowercase));"
    max_id_result = SQLite.Query(connection, max_id_query) |> DataFrame
    max_id = max_id_result[1, 1]
    if !isnothing(max_id)
      update_sequence_sql = "UPDATE sqlite_sequence SET seq = $(max_id + 1) WHERE name = '$(string(model.name |> lowercase))';"
      SQLite.execute(connection, update_sequence_sql)
    end
  end
end

function update(objct::SQLObject; table_alias::Union{Nothing, SQLTableAlias} = nothing, connection::Union{Nothing, LibPQ.Connection, SQLite.DB} = nothing)
  model = objct.model
  settings = config[model.connect_key]
  connection === nothing && (connection = settings.connections) # TODO -- i need create a mode to handle with pools and create a function to this
 
  instruction = build(objct, table_alias=table_alias, connection=connection) 

  # raize error if is used join in update
  instruction.row_join |> isempty || throw("Error in update, the join is not allowed in update")

  # check if is allowed to insert
  !settings.change_data && throw(ArgumentError("Error in update, the connection \e[4m\e[31m$(model.connect_key)\e[0m not allowed to update"))

  # don't allow to update a field without filter
  instruction._where |> isempty && throw("Error in update, the update must have a filter")
  
  # colect name of the fields
  fields = model.field_names

  # check if the fields need to be updated automatically
  for field in fields
    if !haskey(objct.insert, field)
      # check if field allow null or if exist a default value
      if model.fields[field].type == "TIMESTAMPTZ" && (model.fields[field].auto_now)
        objct.insert[field] = model.fields[field].formater(now(), settings.time_zone)
      elseif model.fields[field].type == "DATE" && (model.fields[field].auto_now)
        objct.insert[field] = model.fields[field].formater(today())      
      end
    end
  end

  # check if the fields are in objct.insert
  for field in keys(objct.insert)    
    # check if the create has a field that not exist in the model
    in(field, fields) || throw("""Error in update, the field "$(field)" not found in $(model.name)""")
    # check if field is a primary key and not allow to update
    model.fields[field].primary_key && throw("Error in update, the field \e[4m\e[31m$(field)\e[0m is a primary key and not allow to update")
    # check if the field has max_length and validate
    hasfield(typeof(model.fields[field]), :max_length) && length(objct.insert[field]) > model.fields[field].max_length && error("""Error in update, the field \e[4m\e[31m$(field)\e[0m has a max_length of \e[4m\e[32m$(model.fields[field].max_length)\e[0m, but the value has \e[4m\e[31m$(length(q.object.create[field]))\e[0m""")
    # check if the field has max_digits and validate
    if hasfield(typeof(model.fields[field]), :max_digits)
      value_str = string(objct.insert[field])
      integer_part, fractional_part = split(value_str, ".")
      total_digits = length(replace(integer_part, "-" => "")) + length(fractional_part)
      if total_digits > model.fields[field].max_digits
        error("""Error in update, the field \e[4m\e[31m$(field)\e[0m has a max_digits of \e[4m\e[32m$(model.fields[field].max_digits)\e[0m, but the value has \e[4m\e[31m$(total_digits)\e[0m""")
      end
    end
  end
   

  set_clause = join([ "$(field) = $(objct.insert[field] |> model.fields[field].formater)" for field in keys(objct.insert) ], ", ")

  # construct the SQL statement
  sql = """
    UPDATE $(string(model.name)) as $(instruction.alias)
    SET $(set_clause)
    WHERE $(join(instruction._where, " AND \n   "))
  """

  # @info sql

  # execute the SQL statement
  if connection isa LibPQ.Connection
    LibPQ.execute(connection, sql)
  elseif connection isa SQLite.DB
    SQLite.execute(connection, sql)
  else
    throw("Unsupported connection type")
  end

  return nothing
end

function fetch(connection::LibPQ.Connection, sql::String)
  return LibPQ.execute(connection, sql)
end

export list
# create a function like a list from Django query
function list(objct::SQLObjectHandler)
  connection = config[objct.object.model.connect_key].connections

  sql = query(objct, connection=connection)
  return fetch(connection, sql)
end

# ---
# Execute bulk insert and update
#

export bulk_insert

function bulk_insert(objct::SQLObjectHandler, df::DataFrames.DataFrame; columns::Vector{Union{String, Pair{String, String}}} = Union{String, Pair{String, String}}[], chunk_size::Int64 = 1000) 
  model = objct.object.model
  settings = config[model.connect_key]
  connection = settings.connections

  # check if is allowed to insert
  !settings.change_data && throw(ArgumentError("Error in bulk_insert, the connection \e[4m\e[31m$(model.connect_key)\e[0m not allowed to insert"))

  # If no rows then nothing to do
  if size(df, 1) == 0
    @warn("Warning in bulk_insert, the DataFrame is empty")
    return nothing
  end

  # colect name of the fields
  fields = model.field_names
  fields_df::Vector{String} = []
  if !isempty(columns)   
    if length(columns) > 0
      for column in columns
        if column isa Pair
          rename!(df, column.first => column.second)
          push!(fields_df, column.second)
        else
          push!(fields_df, column)
        end
      end
    end
  else
    for field in names(df)
      fld_ = field |> lowercase
      if fld_ in fields
        push!(fields_df, fld_)
      end
      if fld_ != field
        DataFrames.rename!(df, field => fld_)
      end
    end    
  end

  # check if missing fields in fields_df are not null or dont have a default value
  pk_exist::Bool = false
  pk_field::Vector{String} = []
  for field in fields
    if !in(field, fields_df)
      if model.fields[field].default !== nothing
        df[!, field] = model.fields[field].default
        push!(fields_df, field)
      elseif model.fields[field].type == "TIMESTAMPTZ" && (model.fields[field].auto_now_add || model.fields[field].auto_now)
        df[!, field] = model.fields[field].formater(now(), settings.time_zone)
        push!(fields_df, field)
      elseif model.fields[field].type == "DATE" && (model.fields[field].auto_now_add || model.fields[field].auto_now)
        df[!, field] = model.fields[field].formater(today())
        push!(fields_df, field)
      elseif model.fields[field].null || model.fields[field].primary_key
        continue      
      else
        @infiltrate
        throw("Error in bulk_insert, the field \e[4m\e[31m$(field)\e[0m not allow null")
      end
    else      
      if  model.fields[field].primary_key
        pk_exist = true
        push!(pk_field, field)
      end
    end
  end

  # check if the fields_df are not in fields
  for field in fields_df
    in(field, fields) || throw("""Error in bulk_insert, the field \e[4m\e[31m$(field)\e[0m not found in \e[4m\e[32m$(model.name)\e[0m""")
  end

  # Build a list of row value strings by applying each model field formatter.
  rows = String[]
  count::Int64 = 0
  total::Int64 = size(df, 1)
  for (index, row) in enumerate(eachrow(df))
    values = String[]
    try
      values = [model.fields[field].formater(row[field]) for field in fields]
    catch e
      _depuration_values_bulk_insert(fields, model, row, index)
      throw("Error in bulk_insert, the row $(index) has a problem: $(e)")
    end
    push!(rows, "($(join(values, ", ")))")
    count += 1
    if count == chunk_size || index == total
      bulk_insert(model, connection, fields, rows, pk_exist, pk_field)
      count = 0
      rows = String[]
    end
  end  

  return nothing
  
end

function _depuration_values_bulk_insert(fields::Vector{String}, model::PormGModel, row::DataFrames.DataFrameRow, index::Int64)
  for field in fields
    try
      model.fields[field].formater(row[field])
    catch e
      throw(ArgumentError("Error in bulk_insert, the field \e[4m\e[31m$(field)\e[0m in row \e[4m\e[31m$(index)\e[0m has a value that can't be formatted: \e[4m\e[31m$(row[field])\e[0m"))
    end
  end  
end

function bulk_insert(model::PormGModel, connection::LibPQ.Connection, fields::Vector{String}, rows::Vector{String}, pk_exist::Bool, pk_field::Vector{String})
  # Construct the bulk insert SQL.
  sql = """
  INSERT INTO $(string(model.name)) ($(join(fields, ", ")))
  VALUES $(join(rows, ", "))
  """

  # @info sql

  # Execute the query for the given connection type.
  if connection isa LibPQ.Connection
    LibPQ.execute(connection, sql)
  elseif connection isa SQLite.DB
    SQLite.execute(connection, sql)
  else
    throw("Unsupported connection type")
  end

  pk_exist && _update_sequence(model, connection, pk_field)

end

export bulk_update

function bulk_update(objct::SQLObjectHandler, df::DataFrames.DataFrame; 
  columns::Vector{Union{String, Pair{String, String}}}=Union{String, Pair{String, String}}[],
  filters::Vector{Union{String, Pair{String, Any}}}=Union{String, Pair{String, Any}}[],
  chunk_size::Int64=1000)
  model = objct.object.model
  settings = config[model.connect_key]
  connection = settings.connections

  # check if is allowed to insert
  !settings.change_data && throw(ArgumentError("Error in bulk_update, the connection \e[4m\e[31m$(model.connect_key)\e[0m not allowed to update"))

  # If no rows then nothing to do
  if size(df, 1) == 0
    @warn("Warning in bulk_update, the DataFrame is empty")
    return nothing
  end

  # colect the filters
  pks = [field for field in keys(model.fields) if model.fields[field].primary_key]
  dinanic_filters::Vector{String} = []
  static_filters::Vector{Pair{String, Any}} = []
  if !isempty(filters)
    for filter in filters
      if filter isa Pair
        push!(static_filters, filter)
      else
        push!(dinanic_filters, filter)
      end
    end
  else
    dinanic_filters = pks
  end

  # colect name of the fields
  fields = model.field_names
  fields_df::Vector{String} = []
  if !isempty(columns)   
    if length(columns) > 0
      for column in columns
        if column isa Pair
          rename!(df, column.first => column.second)
          push!(fields_df, column.second)
        else
          push!(fields_df, column)
        end
      end
    end
  else
    for field in names(df)
      fld_ = field |> lowercase
      if fld_ in fields
        push!(fields_df, fld_)
      end
      if fld_ != field
        DataFrames.rename!(df, field => fld_)
      end
    end    
  end  

  # check if missing fields in fields_df are updated automatically
  pk_exist::Bool = false
  pk_field::Vector{String} = []
  for field in fields
    if !in(field, fields_df)      
      if model.fields[field].type == "TIMESTAMPTZ" &&  model.fields[field].auto_now
        df[!, field] = model.fields[field].formater(now(), settings.time_zone)
        push!(fields_df, field)
      elseif model.fields[field].type == "DATE" && model.fields[field].auto_now
        df[!, field] = model.fields[field].formater(today())
        push!(fields_df, field)     
      end    
    else
      if model.fields[field].primary_key
        pk_exist = true
        push!(pk_field, field)
      end
    end
  end  

  # check if the fields_df are not in fields
  for field in fields_df
    in(field, fields) || @error("""Error in bulk_update, the field \e[4m\e[31m$(field)\e[0m not found in \e[4m\e[32m$(model.name)\e[0m""")
  end

  # Build a list of row value strings by applying each model field formatter.
  rows = String[]
  set_columns = join([ "$(field) = source.$(field)::$(model.fields[field].type |> lowercase)" for field in fields_df if !(field in pk_field) ], ", ")
  count::Int64 = 0
  total::Int64 = size(df, 1)
  for (index, row) in enumerate(eachrow(df))
  values = String[]
  try
    values = [model.fields[field].formater(row[field]) for field in fields_df]
  catch e
    _depuration_values_bulk_insert(fields_df, model, row, index)
    throw("Error in bulk_update, the row $(index) has a problem: $(e)")
  end
  push!(rows, "($(join(values, ", ")))")
  count += 1
  if count == chunk_size || index == total
    bulk_update(model, connection, fields_df, rows, pk_exist, pk_field, set_columns)
    count = 0
    rows = String[]
  end
  end

  return nothing
  
end

function bulk_update(model::PormGModel, connection::LibPQ.Connection, fields::Vector{String}, rows::Vector{String}, pk_exist::Bool, pk_field::Vector{String}, set_columns::String)
  # Construct the bulk update SQL.
  pk_field_str = pk_field[1] # TODO: support multiple primary keys
  sql = """
  UPDATE $(string(model.name)) AS target
  SET $(set_columns)
  FROM (VALUES $(join([join(split(row, ", "), ", ") for row in rows], ","))) AS source ($(join(fields, ",")))
  WHERE target.$(pk_field_str) = source.$(pk_field_str);
  """

  # @info sql

  # Execute the query for the given connection type.
  if connection isa LibPQ.Connection
    LibPQ.execute(connection, sql)
  elseif connection isa SQLite.DB
    SQLite.execute(connection, sql)
  else    
    throw("Unsupported connection type")
  end
end







end

