<#
.SYNOPSIS
    Checks disk free space and alerts when a volume drops below threshold.

.DESCRIPTION
    STATUS: Scaffold only -- not yet implemented.

    Planned behavior: check free space on configured volumes against a
    threshold pulled from config (not hardcoded), and send an alert
    (channel TBD -- see docs/DECISIONS.md) only when the threshold is
    crossed, with a cooldown so it does not spam on every scheduled run.

.NOTES
    Design decisions for this script are logged in docs/DECISIONS.md as
    they are made.
#>

#Requires -Version 5.1

# TODO: param block, threshold check, alert dispatch, cooldown/state tracking
