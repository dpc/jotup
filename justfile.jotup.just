# Run all fuzz targets with specified arguments
# Default: run each target for 10 seconds
fuzz-all args="-max_total_time=10":
    cargo fuzz run parse -- {{args}}
    cargo fuzz run html -- {{args}}
    cargo fuzz run compare_renderers -- {{args}}

# Run a specific fuzz target
fuzz target args="-max_total_time=10":
    cargo fuzz run {{target}} -- {{args}}

# List all available fuzz targets
fuzz-list:
    cargo fuzz list
