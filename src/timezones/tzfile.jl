# Parsing tzfiles (ftp://ftp.iana.org/tz/code/tzfile.5.txt)
immutable TransitionTimeInfo
    gmtoff::Int32     # tt_gmtoff
    isdst::Int8       # tt_isdst
    abbrindex::UInt8  # tt_abbrind
end

abbreviation(chars::Array{UInt8}, offset::Integer=1) = ascii(pointer(chars[offset:end]))

function read_tzfile(io::IO, name::AbstractString)
    version = _read_tzfile_header(io)
    transitions = _read_tzfile_data(io)
    if version in ('2', '3')
        # Another even better transition table after this first one
        _read_tzfile_header(io)
        transitions = _read_tzfile_data(io, timesize=Int64, has_posix_str=true)
    end
    return VariableTimeZone(Symbol(name), transitions)
end

function _read_tzfile_header(io)
    magic = readbytes(io, 4)
    @assert magic == b"TZif" "Magic file identifier \"TZif\" not found."
    # A byte indicating the version of the file's format: '\0', '2', '3'
    version = Char(read(io, UInt8))
    readbytes(io, 15)  # Fifteen bytes reserved for future use
    return version
end

function _read_tzfile_data{T<:Integer}(io::IO; timesize::Type{T}=Int32, has_posix_str=false)
    tzh_ttisgmtcnt = ntoh(read(io, Int32))  # Number of UTC/local indicators
    tzh_ttisstdcnt = ntoh(read(io, Int32))  # Number of standard/wall indicators
    tzh_leapcnt = ntoh(read(io, Int32))  # Number of leap seconds
    tzh_timecnt = ntoh(read(io, Int32))  # Number of transition dates
    tzh_typecnt = ntoh(read(io, Int32))  # Number of TransitionTimeInfos (must be > 0)
    tzh_charcnt = ntoh(read(io, Int32))  # Number of timezone abbreviation characters

    transition_times = Array{timesize}(tzh_timecnt)
    for i in eachindex(transition_times)
        transition_times[i] = ntoh(read(io, timesize))
    end
    lindexes = Array{UInt8}(tzh_timecnt)
    for i in eachindex(lindexes)
        lindexes[i] = ntoh(read(io, UInt8)) + 1 # Julia uses 1 indexing
    end
    ttinfo = Array{TransitionTimeInfo}(tzh_typecnt)
    for i in eachindex(ttinfo)
        ttinfo[i] = TransitionTimeInfo(
            ntoh(read(io, Int32)),
            ntoh(read(io, Int8)),
            ntoh(read(io, UInt8)) + 1 # Julia uses 1 indexing
        )
    end
    abbrs = Array{UInt8}(tzh_charcnt)
    for i in eachindex(abbrs)
        abbrs[i] = ntoh(read(io, UInt8))
    end

    # leap seconds (We don't use these)
    leapseconds_time = Array{timesize}(tzh_leapcnt)
    leapseconds_seconds = Array{Int32}(tzh_leapcnt)
    for i in eachindex(leapseconds_time)
        leapseconds_time[i] = ntoh(read(io, timesize))
        leapseconds_seconds[i] = ntoh(read(io, Int32))
    end
    # standard/wall and UTC/local indicators (We don't use these)
    isstd = Array{Int8}(tzh_ttisstdcnt)
    for i in eachindex(isstd)
        isstd[i] = ntoh(read(io, Int8))
    end
    isgmt = Array{Int8}(tzh_ttisgmtcnt)
    for i in eachindex(isgmt)
        isgmt[i] = ntoh(read(io, Int8))
    end
    # We don't use this yet
    if has_posix_str
        readline(io)
        posix_str = readline(io)
    end

    # Now build the timezone transitions
    if tzh_timecnt == 0
        abbr = abbreviation(abbrs, ttinfo[1].abbrindex)
        return FixedTimeZone(Symbol(abbr), Offset(ttinfo[1].gmtoff))
    else
        # Calculate transition info
        transitions = Transition[]
        utc = dst = 0
        for i in eachindex(transition_times)
            info = ttinfo[lindexes[i]]

            # Since the tzfile does not contain the DST offset we need to
            # attempt to calculate it.
            if info.isdst == 0
                utc = info.gmtoff
                dst = 0
            elseif dst == 0
                # isdst == false and the last DST offset was 0:
                # assume that only the DST offset has changed
                dst = info.gmtoff - utc
            else
                # isdst == false and the last DST offset was not 0:
                # assume that only the GMT offset has changed
                utc = info.gmtoff - dst
            end

            # Sometimes it likes to be fancy and have multiple names in one for
            # example "WSST" at abbrindex 5 turns into "SST" at abbrindex 6
            abbr = abbreviation(abbrs, info.abbrindex)
            tz = FixedTimeZone(abbr, utc, dst)

            if isempty(transitions) || last(transitions).zone != tz
                push!(transitions, Transition(unix2datetime(transition_times[i]), tz))
            end
        end
        return transitions
    end
end