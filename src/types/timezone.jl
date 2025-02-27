# Thread-local TimeZone cache, which caches time zones _per thread_, allowing thread-safe
# caching. Note that this means the cache will grow in size, and may store redundant objects
# accross multiple threads, but this extra space usage allows for fast, lock-free access
# to the cache, while still being thread-safe.
const THREAD_TZ_CACHES = Vector{Dict{String,Tuple{TimeZone,Class}}}()

# Based upon the thread-safe Global RNG implementation in the Random stdlib:
# https://github.com/JuliaLang/julia/blob/e4fcdf5b04fd9751ce48b0afc700330475b42443/stdlib/Random/src/RNGs.jl#L369-L385
@inline _tz_cache() = _tz_cache(Threads.threadid())
@noinline function _tz_cache(tid::Int)
    0 < tid <= length(THREAD_TZ_CACHES) || _tz_cache_length_assert()
    if @inbounds isassigned(THREAD_TZ_CACHES, tid)
        @inbounds cache = THREAD_TZ_CACHES[tid]
    else
        cache = eltype(THREAD_TZ_CACHES)()
        @inbounds THREAD_TZ_CACHES[tid] = cache
    end
    return cache
end
@noinline _tz_cache_length_assert() = @assert false "0 < tid <= length(THREAD_TZ_CACHES)"

function _reset_tz_cache()
    # ensures that we didn't save a bad object
    resize!(empty!(THREAD_TZ_CACHES), Threads.nthreads())
end

"""
    TimeZone(str::AbstractString) -> TimeZone

Constructs a `TimeZone` subtype based upon the string. If the string is a recognized
standard time zone name then data is loaded from the compiled IANA time zone database.
Otherwise the string is parsed as a fixed time zone.

A list of recognized standard and legacy time zones names can is available by running
`timezone_names()`. Supported fixed time zone string formats can be found in docstring for
[`FixedTimeZone(::AbstractString)`](@ref).

## Examples
```jldoctest
julia> TimeZone("Europe/Warsaw")
Europe/Warsaw (UTC+1/UTC+2)

julia> TimeZone("UTC")
UTC
```
"""
TimeZone(::AbstractString)

"""
    TimeZone(str::AbstractString, mask::Class) -> TimeZone

Similar to [`TimeZone(::AbstractString)`](@ref) but allows you to control what time zone
classes are allowed to be constructed with `mask`. Can be used to construct time zones
which are classified as "legacy".

## Examples
```jldoctest
julia> TimeZone("US/Pacific")
ERROR: ArgumentError: The time zone "US/Pacific" is of class `TimeZones.Class(:LEGACY)` which is currently not allowed by the mask: `TimeZones.Class(:FIXED) | TimeZones.Class(:STANDARD)`

julia> TimeZone("US/Pacific", TimeZones.Class(:LEGACY))
US/Pacific (UTC-8/UTC-7)
```
"""
TimeZone(::AbstractString, ::Class)

function TimeZone(str::AbstractString, mask::Class=Class(:DEFAULT))
    # Note: If the class `mask` does not match the time zone we'll still load the
    # information into the cache to ensure the result is consistent.
    tz, class = get!(_tz_cache(), str) do
        tz_path = joinpath(_COMPILED_DIR[], split(str, "/")...)

        if isfile(tz_path)
            open(TZJFile.read, tz_path, "r")(str)
        elseif occursin(FIXED_TIME_ZONE_REGEX, str)
            FixedTimeZone(str), Class(:FIXED)
        elseif !isdir(_COMPILED_DIR[]) || isempty(readdir(_COMPILED_DIR[]))
            # Note: Julia 1.0 supresses the build logs which can hide issues in time zone
            # compliation which result in no tzdata time zones being available.
            throw(ArgumentError(
                "Unable to find time zone \"$str\". Try running `TimeZones.build()`."
            ))
        else
            throw(ArgumentError("Unknown time zone \"$str\""))
        end
    end

    if mask & class == Class(:NONE)
        throw(ArgumentError(
            "The time zone \"$str\" is of class `$(repr(class))` which is " *
            "currently not allowed by the mask: `$(repr(mask))`"
        ))
    end

    return tz
end

"""
    @tz_str -> TimeZone

Constructs a `TimeZone` subtype based upon the string at parse time. See docstring of
`TimeZone` for more details.

```julia
julia> tz"Africa/Nairobi"
Africa/Nairobi (UTC+3)
```
"""
macro tz_str(str)
    TimeZone(str)
end

"""
    istimezone(str::AbstractString, mask::Class=Class(:DEFAULT)) -> Bool

Check whether a string is a valid for constructing a `TimeZone` with the provided `mask`.
"""
function istimezone(str::AbstractString, mask::Class=Class(:DEFAULT))
    # Start by performing quick FIXED class test
    if mask & Class(:FIXED) != Class(:NONE) && occursin(FIXED_TIME_ZONE_REGEX, str)
        return true
    end

    # Perform more expensive checks against pre-compiled time zones
    tz, class = get(_tz_cache(), str) do
        tz_path = joinpath(_COMPILED_DIR[], split(str, "/")...)

        if isfile(tz_path)
            # Cache the data since we're already performing the deserialization
            _tz_cache()[str] = open(TZJFile.read, tz_path, "r")(str)
        else
            nothing, Class(:NONE)
        end
    end

    return tz !== nothing && mask & class != Class(:NONE)
end
