# `RelocatableFolders.@path` requires the existance of the referenced root
# directory/file.  We ensure they exist prior to calling `using TimeZones`.
mkpath(joinpath(@__DIR__, "local"))
mkpath(joinpath(@__DIR__, "tzarchive"))
mkpath(joinpath(@__DIR__, "compiled", string(VERSION)))
touch(joinpath(@__DIR__, "active_version"))
touch(joinpath(@__DIR__, "latest"))

import TimeZones

if Sys.iswindows()
    TimeZones.WindowsTimeZoneIDs.build(; force = true)
end
TimeZones.build()

# Ensure the we'll get precompilation during the next import
# which will capture all the build files in deps into the
# RelocatableFolders paths.
touch(joinpath(@__DIR__, "active_version"))
