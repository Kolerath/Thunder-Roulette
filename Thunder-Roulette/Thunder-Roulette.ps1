[CmdletBinding()]
param(
    [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName Microsoft.VisualBasic

$appRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    [System.IO.Path]::GetDirectoryName([Environment]::GetCommandLineArgs()[0])
}
else {
    $PSScriptRoot
}
$dataDirectory = Join-Path $appRoot 'Data'
$profilesDirectory = Join-Path $dataDirectory 'Profiles'
$deletedProfilesDirectory = Join-Path $dataDirectory 'DeletedProfiles'
$profilesFile = Join-Path $dataDirectory 'profiles.json'
$contentFile = Join-Path $dataDirectory 'content-libraries.json'
$domainSettingsFile = Join-Path $dataDirectory 'domain-settings.json'
$progressionFile = Join-Path $dataDirectory 'progression-catalog.json'
$defaultProgressionFile = Join-Path $appRoot 'DefaultProgressionCatalog.json'
$xamlFile = Join-Path $appRoot 'MainWindow.xaml'
$manageXamlFile = Join-Path $appRoot 'ManageWindow.xaml'
$challengeEditorXamlFile = Join-Path $appRoot 'ChallengeEditorWindow.xaml'
$sessionXamlFile = Join-Path $appRoot 'SessionWindow.xaml'

$nations = [ordered]@{
    USA             = 'USA.png'
    Germany         = 'Germany.png'
    USSR            = 'USSR.png'
    'Great Britain' = 'Great-Britain.png'
    Japan           = 'Japan.png'
    China           = 'China.png'
    Italy           = 'Italy.png'
    France          = 'France.png'
    Sweden          = 'Sweden.png'
    Israel          = 'Israel.png'
}

$domains = @(
    [pscustomobject]@{ Id='Any'; Name='Any mode' }
    [pscustomobject]@{ Id='Ground'; Name='Ground' }
    [pscustomobject]@{ Id='Air'; Name='Air' }
    [pscustomobject]@{ Id='Naval'; Name='Naval' }
)
$defaultDomainNationEligibility = [ordered]@{
    Ground = @($nations.Keys)
    Air = @($nations.Keys)
    Naval = @('USA','Germany','USSR','Great Britain','Japan','Italy','France')
}

function Normalize-Domain([string] $domain) {
    if ($domain -in @('Ground','Air','Naval')) { return $domain }
    return 'Any'
}

function Save-DomainSettings {
    [pscustomobject]@{ NationEligibility = $script:domainNationEligibility } |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $domainSettingsFile -Encoding UTF8
}

function Load-DomainSettings {
    $loaded = $null
    try { $loaded = (Get-Content -LiteralPath $domainSettingsFile -Raw | ConvertFrom-Json).NationEligibility } catch {}
    $normalized = [ordered]@{}
    foreach ($domain in @('Ground','Air','Naval')) {
        $values = if ($loaded -and $loaded.PSObject.Properties[$domain]) { @($loaded.$domain) } else { @($defaultDomainNationEligibility[$domain]) }
        $values = @($nations.Keys | Where-Object { $_ -in $values })
        if ($values.Count -eq 0) { $values = @($defaultDomainNationEligibility[$domain]) }
        $normalized[$domain] = $values
    }
    $script:domainNationEligibility = $normalized
    Save-DomainSettings
}

function Get-EligibleNations([string] $domain) {
    $domain = Normalize-Domain $domain
    if ($domain -eq 'Any') { return @($nations.Keys) }
    return @($script:domainNationEligibility[$domain])
}

function Test-ContentDomain($item, [string] $domain) {
    $selected = Normalize-Domain $domain
    $itemDomain = if ($item.PSObject.Properties['Domain']) { Normalize-Domain ([string]$item.Domain) } else { 'Any' }
    return $selected -eq 'Any' -or $itemDomain -eq 'Any' -or $itemDomain -eq $selected
}

function Get-EligibleChallenges { return @($script:challenges | Where-Object { Test-ContentDomain $_ $script:activeSettings.Domain }) }
function Get-EligibleFunModes { return @($script:funModes | Where-Object { Test-ContentDomain $_ $script:activeSettings.Domain }) }
function Get-EligibleProgressionTracks([string] $domain) {
    $domain = Normalize-Domain $domain
    if ($domain -eq 'Any') { return @($script:progressionCatalog.Tracks) }
    return @($script:progressionCatalog.Tracks | Where-Object Domain -eq $domain)
}

# War Thunder uses thirds rounded to one decimal: .0, .3, .7.
$brStages = @(
    foreach ($whole in 1..14) {
        foreach ($fraction in @(0.0, 0.3, 0.7)) {
            $rating = $whole + $fraction
            if ($rating -le 14.0) { [double]$rating }
        }
    }
)

$challenges = @(
    [pscustomobject]@{ Id='caliber-climb'; Name='Caliber Climb'; Objective='Get 3 kills using your current campaign caliber.'; Reward='Advance one weapon stage.'; Trackers=@([pscustomobject]@{Id='caliber-kills';Label='Kills with the current caliber';Type='Counter';Target=3;Required=$true}); RewardAction=[pscustomobject]@{Type='TrackSteps';Steps=1}; FailureAction=[pscustomobject]@{Type='None';Steps=0} }
    [pscustomobject]@{ Id='combined-arms'; Name='Combined Arms'; Objective='Get 2 tank kills and 1 plane kill in the same match.'; Reward='Advance one BR stage.'; Trackers=@([pscustomobject]@{Id='tank-kills';Label='Tank kills';Type='Counter';Target=2;Required=$true},[pscustomobject]@{Id='plane-kills';Label='Plane kills';Type='Counter';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='triple-role'; Name='Three Roles'; Objective='Earn a kill with three different vehicle classes.'; Reward='Advance one BR stage.'; Trackers=@([pscustomobject]@{Id='roles';Label='Vehicle classes with a kill';Type='Counter';Target=3;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='zone-keeper'; Name='Zone Keeper'; Objective='Capture a zone, then destroy an enemy while defending it.'; Reward='Reroll your nation if desired.'; Trackers=@([pscustomobject]@{Id='capture';Label='Captured a zone';Type='Checkbox';Target=1;Required=$true},[pscustomobject]@{Id='defence';Label='Defensive kill';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='None';Steps=0} }
    [pscustomobject]@{ Id='wing-clipper'; Name='Wing Clipper'; Objective='Destroy an aircraft using a ground vehicle.'; Reward='Advance one BR stage.'; Trackers=@([pscustomobject]@{Id='aircraft';Label='Aircraft destroyed from the ground';Type='Counter';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='one-life'; Name='One Life'; Objective='Get 3 kills without losing your first vehicle.'; Reward='Advance one BR stage.'; Trackers=@([pscustomobject]@{Id='kills';Label='Kills';Type='Counter';Target=3;Required=$true},[pscustomobject]@{Id='survive';Label='First vehicle survived';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='support-act'; Name='Support Act'; Objective='Score 3 assists and help capture at least one zone.'; Reward='Failure does not count against the run.'; Trackers=@([pscustomobject]@{Id='assists';Label='Assists';Type='Counter';Target=3;Required=$true},[pscustomobject]@{Id='capture';Label='Helped capture a zone';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='None';Steps=0} }
    [pscustomobject]@{ Id='light-brigade'; Name='Light Brigade'; Objective='Use only light tanks and tank destroyers for one match.'; Reward='Advance one BR stage after a victory.'; Trackers=@([pscustomobject]@{Id='lineup';Label='Used only allowed vehicle classes';Type='Checkbox';Target=1;Required=$true},[pscustomobject]@{Id='victory';Label='Match victory';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='heavy-metal'; Name='Heavy Metal'; Objective='Get 2 kills using a heavy tank without using aircraft.'; Reward='Advance one BR stage.'; Trackers=@([pscustomobject]@{Id='kills';Label='Heavy tank kills';Type='Counter';Target=2;Required=$true},[pscustomobject]@{Id='no-air';Label='Used no aircraft';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='BRSteps';Steps=1} }
    [pscustomobject]@{ Id='squad-variety'; Name='Squad Variety'; Objective='Every squad member must spawn a different vehicle class first.'; Reward='Everyone may reroll their BR.'; Trackers=@([pscustomobject]@{Id='variety';Label='Different first-spawn classes confirmed';Type='Checkbox';Target=1;Required=$true}); RewardAction=[pscustomobject]@{Type='None';Steps=0} }
)

$funModes = @(
    [pscustomobject]@{ Id = 'light-tanks'; Name = 'Light Tanks Only'; Rule = 'Your lineup may contain only light tanks.' }
    [pscustomobject]@{ Id = 'derp-guns'; Name = 'Derp Guns Only'; Rule = 'Bring vehicles chosen for gloriously oversized, slow-firing guns.' }
    [pscustomobject]@{ Id = 'open-tops'; Name = 'Open-Tops Only'; Rule = 'Every ground vehicle must have an exposed or open fighting compartment.' }
    [pscustomobject]@{ Id = 'wheels-only'; Name = 'Wheels Only'; Rule = 'No tracks allowed: use wheeled ground vehicles only.' }
    [pscustomobject]@{ Id = 'tank-destroyers'; Name = 'Tank Destroyers Only'; Rule = 'Build the lineup entirely from tank destroyers.' }
    [pscustomobject]@{ Id = 'aggressive-spaa'; Name = 'Aggressive SPAA'; Rule = 'Use SPAA as aggressively as legally and mechanically possible.' }
    [pscustomobject]@{ Id = 'no-aircraft'; Name = 'No Aircraft'; Rule = 'Remain firmly on the ground for the entire match.' }
    [pscustomobject]@{ Id = 'one-plus-backups'; Name = 'One Vehicle + Backups'; Rule = 'Choose one vehicle; additional spawns must use backups of that vehicle.' }
    [pscustomobject]@{ Id = 'maximum-caliber'; Name = 'Maximum Caliber'; Rule = 'Build around the largest gun caliber available in your chosen nation and BR.' }
    [pscustomobject]@{ Id = 'same-vehicle'; Name = 'Same Vehicle Squad'; Rule = 'Every squad member brings the same vehicle.' }
)

$defaultChallenges = @(($challenges | ConvertTo-Json -Depth 8 | ConvertFrom-Json))
$defaultFunModes = @($funModes | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Rule = $_.Rule; Domain = $(if ($_.Id -in @('light-tanks','derp-guns','open-tops','wheels-only','tank-destroyers','aggressive-spaa','no-aircraft')) { 'Ground' } else { 'Any' }) } })

function ConvertTo-Challenge($challenge) {
    $default = @($defaultChallenges | Where-Object { $_.Id -eq [string]$challenge.Id } | Select-Object -First 1)
    $legacyCaliberReward = [string]$challenge.Id -eq 'caliber-climb' -and
        [string]$challenge.Reward -eq 'Complete the full lineup order.' -and
        $challenge.PSObject.Properties['RewardAction'] -and
        [string]$challenge.RewardAction.Type -eq 'None'
    $hasTrackers = $challenge.PSObject.Properties['Trackers'] -and @($challenge.Trackers).Count -gt 0
    $legacyCaliberTracker = [string]$challenge.Id -eq 'caliber-climb' -and $hasTrackers -and
        @($challenge.Trackers).Count -eq 1 -and [string]$challenge.Trackers[0].Id -eq 'order'
    $legacyGenericTracker = $hasTrackers -and $default.Count -gt 0 -and @($challenge.Trackers).Count -eq 1 -and [string]$challenge.Trackers[0].Id -eq 'complete' -and [string]$default[0].Trackers[0].Id -ne 'complete'
    $trackers = if ($legacyGenericTracker -or $legacyCaliberTracker) {
        @(($default[0].Trackers | ConvertTo-Json -Depth 5 | ConvertFrom-Json))
    }
    elseif ($hasTrackers) {
        @($challenge.Trackers)
    }
    elseif ($default.Count -gt 0) {
        @(($default[0].Trackers | ConvertTo-Json -Depth 5 | ConvertFrom-Json))
    }
    else {
        @([pscustomobject]@{ Id='complete'; Label='Objective completed'; Type='Checkbox'; Target=1; Required=$true })
    }
    $normalTrackers = @(
        foreach ($tracker in $trackers) {
            [pscustomobject]@{
                Id = if ($tracker.PSObject.Properties['Id']) { [string]$tracker.Id } else { [guid]::NewGuid().ToString('N') }
                Label = [string]$tracker.Label
                Type = if ([string]$tracker.Type -eq 'Counter') { 'Counter' } else { 'Checkbox' }
                Target = if ($tracker.PSObject.Properties['Target']) { [math]::Max(1, [int]$tracker.Target) } else { 1 }
                Required = if ($tracker.PSObject.Properties['Required']) { [bool]$tracker.Required } else { $true }
            }
        }
    )
    $rewardAction = if ($legacyGenericTracker -or $legacyCaliberReward) {
        $default[0].RewardAction
    }
    elseif ($challenge.PSObject.Properties['RewardAction']) {
        $challenge.RewardAction
    }
    elseif ($default.Count -gt 0) {
        $default[0].RewardAction
    }
    elseif ([string]$challenge.Reward -match 'BR') {
        [pscustomobject]@{ Type='BRSteps'; Steps=1 }
    }
    else {
        [pscustomobject]@{ Type='None'; Steps=0 }
    }
    $failureAction = if ($challenge.PSObject.Properties['FailureAction']) { $challenge.FailureAction } else { [pscustomobject]@{ Type='None'; Steps=0 } }
    $normalizedRewardType = if ([string]$rewardAction.Type -in @('BRSteps','TrackSteps')) { [string]$rewardAction.Type } else { 'None' }
    $normalizedRewardSteps = if ($rewardAction.PSObject.Properties['Steps']) { [math]::Max(0, [int]$rewardAction.Steps) } else { 0 }
    $normalizedFailureType = switch ([string]$failureAction.Type) {
        'BRStepsDown' { if ($normalizedRewardType -eq 'BRSteps') { 'BRStepsDown' } else { 'None' } }
        'TrackStepsDown' { if ($normalizedRewardType -eq 'TrackSteps') { 'TrackStepsDown' } else { 'None' } }
        default { 'None' }
    }
    $normalizedFailureSteps = if ($normalizedFailureType -eq 'BRStepsDown') {
        if ($normalizedRewardSteps -ge 3) { 3 } else { 1 }
    }
    elseif ($normalizedFailureType -eq 'TrackStepsDown') { 1 }
    else { 0 }
    return [pscustomobject]@{
        Id = [string]$challenge.Id; Name = [string]$challenge.Name
        Domain = if ($challenge.PSObject.Properties['Domain']) { Normalize-Domain ([string]$challenge.Domain) } elseif ([string]$challenge.Id -in @('combined-arms','wing-clipper','light-brigade','heavy-metal')) { 'Ground' } else { 'Any' }
        RecordingMode = if ($challenge.PSObject.Properties['RecordingMode'] -and [string]$challenge.RecordingMode -eq 'Simple') { 'Simple' } else { 'Detailed' }
        Objective = if ($legacyCaliberReward -or $legacyCaliberTracker) { [string]$default[0].Objective } else { [string]$challenge.Objective }
        Reward = if ($legacyCaliberReward -or $legacyCaliberTracker) { [string]$default[0].Reward } else { [string]$challenge.Reward }
        Trackers = $normalTrackers
        RewardAction = [pscustomobject]@{
            Type = $normalizedRewardType
            Steps = $normalizedRewardSteps
        }
        FailureAction = [pscustomobject]@{
            Type = $normalizedFailureType
            Steps = $normalizedFailureSteps
        }
    }
}

function ConvertTo-FunMode($funMode) {
    return [pscustomobject]@{
        Id = [string]$funMode.Id
        Name = [string]$funMode.Name
        Rule = [string]$funMode.Rule
        Domain = if ($funMode.PSObject.Properties['Domain']) { Normalize-Domain ([string]$funMode.Domain) } elseif ([string]$funMode.Id -in @('light-tanks','derp-guns','open-tops','wheels-only','tank-destroyers','aggressive-spaa','no-aircraft')) { 'Ground' } else { 'Any' }
    }
}

function Save-ContentLibraries {
    [pscustomobject]@{ Challenges = @($script:challenges); FunModes = @($script:funModes) } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $contentFile -Encoding UTF8
}

function Load-ContentLibraries {
    try {
        $library = Get-Content -LiteralPath $contentFile -Raw | ConvertFrom-Json
        $loadedChallenges = @($library.Challenges | ForEach-Object { ConvertTo-Challenge $_ })
        $loadedFunModes = @($library.FunModes | ForEach-Object { ConvertTo-FunMode $_ })
        if ($loadedChallenges.Count -eq 0 -or $loadedFunModes.Count -eq 0) { throw 'Content libraries cannot be empty.' }
        $script:challenges = $loadedChallenges
        $script:funModes = $loadedFunModes
        Save-ContentLibraries
    }
    catch {
        $script:challenges = @($defaultChallenges | ForEach-Object { ConvertTo-Challenge $_ })
        $script:funModes = @($defaultFunModes | ForEach-Object { ConvertTo-FunMode $_ })
        Save-ContentLibraries
    }
}

function Format-DiameterLabel([double] $minimum, [double] $maximum) {
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $minimumText = $minimum.ToString('0.###', $culture)
    if ([math]::Abs($maximum - $minimum) -lt 0.000001) { return "$minimumText mm" }
    return "$minimumText-$($maximum.ToString('0.###', $culture)) mm"
}

function ConvertTo-ProgressionStage($stage, [int] $sortOrder) {
    if ($stage -is [ValueType]) {
        $minimum = [double]$stage
        return [pscustomobject]@{
            Id = [guid]::NewGuid().ToString('N'); Type = 'Exact'
            Minimum = $minimum; Maximum = $minimum
            Label = Format-DiameterLabel $minimum $minimum
            Enabled = $true; SortOrder = $sortOrder
        }
    }

    $type = if ($stage.PSObject.Properties['Type']) { [string]$stage.Type } else { 'Exact' }
    $minimum = if ($stage.PSObject.Properties['Minimum']) { [double]$stage.Minimum } else { [double]$stage.Value }
    $maximum = if ($type -eq 'Range' -and $stage.PSObject.Properties['Maximum']) { [double]$stage.Maximum } else { $minimum }
    if ($maximum -lt $minimum) { $temporary = $minimum; $minimum = $maximum; $maximum = $temporary }
    return [pscustomobject]@{
        Id = if ($stage.PSObject.Properties['Id']) { [string]$stage.Id } else { [guid]::NewGuid().ToString('N') }
        Type = if ([math]::Abs($maximum - $minimum) -lt 0.000001) { 'Exact' } else { 'Range' }
        Minimum = $minimum; Maximum = $maximum
        Label = if ($stage.PSObject.Properties['Label'] -and -not [string]::IsNullOrWhiteSpace([string]$stage.Label)) { [string]$stage.Label } else { Format-DiameterLabel $minimum $maximum }
        Enabled = if ($stage.PSObject.Properties['Enabled']) { [bool]$stage.Enabled } else { $true }
        SortOrder = if ($stage.PSObject.Properties['SortOrder']) { [int]$stage.SortOrder } else { $sortOrder }
    }
}

function ConvertTo-ProgressionCatalog($catalog) {
    $tracks = @()
    foreach ($track in @($catalog.Tracks)) {
        $order = 0
        $stages = @(
            foreach ($stage in @($track.Stages)) {
                ConvertTo-ProgressionStage $stage $order
                $order++
            }
        )
        $tracks += [pscustomobject]@{
            Id = [string]$track.Id; Name = [string]$track.Name
            Domain = [string]$track.Domain; Family = [string]$track.Family
            Stages = @($stages | Sort-Object SortOrder, Minimum)
        }
    }
    return [pscustomobject]@{
        SchemaVersion = 1
        Source = if ($catalog.PSObject.Properties['Source']) { $catalog.Source } else { $null }
        Tracks = $tracks
    }
}

function Save-ProgressionCatalog {
    $script:progressionCatalog |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $progressionFile -Encoding UTF8
}

function Load-ProgressionCatalog {
    try {
        if (-not (Test-Path -LiteralPath $progressionFile -PathType Leaf)) { throw 'Create catalog from defaults.' }
        $script:progressionCatalog = ConvertTo-ProgressionCatalog (Get-Content -LiteralPath $progressionFile -Raw | ConvertFrom-Json)
        if (@($script:progressionCatalog.Tracks).Count -eq 0) { throw 'Progression catalog cannot be empty.' }
    }
    catch {
        $script:progressionCatalog = ConvertTo-ProgressionCatalog (Get-Content -LiteralPath $defaultProgressionFile -Raw | ConvertFrom-Json)
        Save-ProgressionCatalog
    }
}

function Restore-ProgressionCatalog {
    $script:progressionCatalog = ConvertTo-ProgressionCatalog (Get-Content -LiteralPath $defaultProgressionFile -Raw | ConvertFrom-Json)
    Save-ProgressionCatalog
}

function Expand-SessionHistoryRecords($items) {
    foreach ($item in @($items)) {
        if ($null -eq $item) { continue }
        if ($item.PSObject.Properties['Id'] -or $item.PSObject.Properties['ChallengeName'] -or $item.PSObject.Properties['StartedAt']) {
            $item
        }
        elseif ($item.PSObject.Properties['value']) {
            Expand-SessionHistoryRecords $item.PSObject.Properties['value'].Value
        }
    }
}

function Get-SessionHistory {
    try {
        $stored = Get-Content -LiteralPath $script:activePaths.SessionHistory -Raw | ConvertFrom-Json
        return @(Expand-SessionHistoryRecords $stored)
    }
    catch { return @() }
}

function Save-SessionHistory($history) {
    $json = ConvertTo-Json -InputObject @($history) -Depth 10
    Set-Content -LiteralPath $script:activePaths.SessionHistory -Value $json -Encoding UTF8
}

function Add-SessionHistoryRecord($record) {
    $history = @(Get-SessionHistory)
    $history = @($history) + @($record)
    $history = @($history | Select-Object -Last 250)
    Save-SessionHistory $history
}

function Save-ProfileStore {
    $script:profileStore |
        ConvertTo-Json -Depth 4 |
        Set-Content -LiteralPath $profilesFile -Encoding UTF8
}

function Initialize-AppData {
    foreach ($directory in @($dataDirectory, $profilesDirectory, $deletedProfilesDirectory)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $profilesFile -PathType Leaf)) {
        $defaultId = [guid]::NewGuid().ToString('N')
        $script:profileStore = [pscustomobject]@{
            LastProfileId = $defaultId
            Profiles = @([pscustomobject]@{ Id = $defaultId; Name = 'Player 1' })
        }
        Save-ProfileStore
    }

    if (-not (Test-Path -LiteralPath $contentFile -PathType Leaf)) {
        $script:challenges = @($defaultChallenges | ForEach-Object { ConvertTo-Challenge $_ })
        $script:funModes = @($defaultFunModes)
        Save-ContentLibraries
    }

    try {
        $script:profileStore = Get-Content -LiteralPath $profilesFile -Raw | ConvertFrom-Json
        $script:profileStore.Profiles = @($script:profileStore.Profiles)
        if ($script:profileStore.Profiles.Count -eq 0) {
            throw 'At least one profile is required.'
        }
    }
    catch {
        $backupId = [guid]::NewGuid().ToString('N')
        $script:profileStore = [pscustomobject]@{
            LastProfileId = $backupId
            Profiles = @([pscustomobject]@{ Id = $backupId; Name = 'Player 1' })
        }
        Save-ProfileStore
    }
}

function Get-ProfilePaths([string] $profileId) {
    $directory = Join-Path $profilesDirectory $profileId
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $queue = Join-Path $directory 'queue.txt'
    $challengeQueue = Join-Path $directory 'challenge-queue.txt'
    $funModeQueue = Join-Path $directory 'fun-mode-queue.txt'
    $brQueue = Join-Path $directory 'br-queue.txt'
    $brBracketQueue = Join-Path $directory 'br-bracket-queue.txt'
    $settings = Join-Path $directory 'settings.json'
    $sessionHistory = Join-Path $directory 'session-history.json'

    if (-not (Test-Path -LiteralPath $queue -PathType Leaf)) {
        New-Item -ItemType File -Path $queue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $challengeQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $challengeQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $funModeQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $funModeQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $brQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $brQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $brBracketQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $brBracketQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $sessionHistory -PathType Leaf)) {
        '[]' | Set-Content -LiteralPath $sessionHistory -Encoding UTF8
    }
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        @{
            ClearSequenceOnExit = $false; Domain = 'Any'; MinimumBR = 1.0; MaximumBR = 14.0; BRRollMode = 'Exact'
            SessionRollNation = $true; SessionRollBR = $true
            SessionRollChallenge = $true; SessionRollFunMode = $true
            CampaignTrackId = 'ground-gun'; CampaignStageIndex = 0; CampaignBR = 1.0; CurrentBRResult = ''; CurrentChallengeId = ''
        } |
            ConvertTo-Json |
            Set-Content -LiteralPath $settings -Encoding UTF8
    }

    return [pscustomobject]@{ Directory = $directory; Queue = $queue; BRQueue = $brQueue; BRBracketQueue = $brBracketQueue; ChallengeQueue = $challengeQueue; FunModeQueue = $funModeQueue; Settings = $settings; SessionHistory = $sessionHistory }
}

function Get-DomainQueuePath([string] $kind) {
    $domain = Normalize-Domain $script:activeSettings.Domain
    if ($domain -eq 'Any') {
        switch ($kind) {
            'Nation' { return $script:activePaths.Queue }
            'Challenge' { return $script:activePaths.ChallengeQueue }
            'FunMode' { return $script:activePaths.FunModeQueue }
        }
    }
    $prefix = switch ($kind) { 'Nation' { 'queue' } 'Challenge' { 'challenge-queue' } 'FunMode' { 'fun-mode-queue' } }
    $path = Join-Path $script:activePaths.Directory ("$prefix-$($domain.ToLowerInvariant()).txt")
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { New-Item -ItemType File -Path $path | Out-Null }
    return $path
}

function Get-ProfileSettings {
    try {
        $saved = Get-Content -LiteralPath $script:activePaths.Settings -Raw | ConvertFrom-Json
        $clearOnExit = if ($saved.PSObject.Properties['ClearSequenceOnExit']) { [bool]$saved.ClearSequenceOnExit } else { $false }
        $minimumBR = if ($saved.PSObject.Properties['MinimumBR']) { [double]$saved.MinimumBR } else { 1.0 }
        $maximumBR = if ($saved.PSObject.Properties['MaximumBR']) { [double]$saved.MaximumBR } else { 14.0 }
        return [pscustomobject]@{
            ClearSequenceOnExit = $clearOnExit
            Domain = if ($saved.PSObject.Properties['Domain']) { Normalize-Domain ([string]$saved.Domain) } else { 'Any' }
            MinimumBR = $minimumBR
            MaximumBR = $maximumBR
            BRRollMode = if ($saved.PSObject.Properties['BRRollMode'] -and [string]$saved.BRRollMode -eq 'Bracket') { 'Bracket' } else { 'Exact' }
            SessionRollNation = if ($saved.PSObject.Properties['SessionRollNation']) { [bool]$saved.SessionRollNation } else { $true }
            SessionRollBR = if ($saved.PSObject.Properties['SessionRollBR']) { [bool]$saved.SessionRollBR } else { $true }
            SessionRollChallenge = if ($saved.PSObject.Properties['SessionRollChallenge']) { [bool]$saved.SessionRollChallenge } else { $true }
            SessionRollFunMode = if ($saved.PSObject.Properties['SessionRollFunMode']) { [bool]$saved.SessionRollFunMode } else { $true }
            CampaignTrackId = if ($saved.PSObject.Properties['CampaignTrackId']) { [string]$saved.CampaignTrackId } else { 'ground-gun' }
            CampaignStageIndex = if ($saved.PSObject.Properties['CampaignStageIndex']) { [math]::Max(0, [int]$saved.CampaignStageIndex) } else { 0 }
            CampaignBR = if ($saved.PSObject.Properties['CampaignBR']) { [double]$saved.CampaignBR } else { $minimumBR }
            CurrentBRResult = if ($saved.PSObject.Properties['CurrentBRResult']) { [string]$saved.CurrentBRResult } else { '' }
            CurrentChallengeId = if ($saved.PSObject.Properties['CurrentChallengeId']) { [string]$saved.CurrentChallengeId } else { '' }
        }
    }
    catch {
        return [pscustomobject]@{
            ClearSequenceOnExit = $false; Domain = 'Any'; MinimumBR = 1.0; MaximumBR = 14.0; BRRollMode = 'Exact'
            SessionRollNation = $true; SessionRollBR = $true
            SessionRollChallenge = $true; SessionRollFunMode = $true
            CampaignTrackId = 'ground-gun'; CampaignStageIndex = 0; CampaignBR = 1.0; CurrentBRResult = ''; CurrentChallengeId = ''
        }
    }
}

function Save-ProfileSettings([bool] $clearSequenceOnExit, [double] $minimumBR, [double] $maximumBR) {
    $sessionRollNation = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['SessionRollNation']) { [bool]$script:activeSettings.SessionRollNation } else { $true }
    $sessionRollBR = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['SessionRollBR']) { [bool]$script:activeSettings.SessionRollBR } else { $true }
    $sessionRollChallenge = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['SessionRollChallenge']) { [bool]$script:activeSettings.SessionRollChallenge } else { $true }
    $sessionRollFunMode = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['SessionRollFunMode']) { [bool]$script:activeSettings.SessionRollFunMode } else { $true }
    $campaignTrackId = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['CampaignTrackId']) { [string]$script:activeSettings.CampaignTrackId } else { 'ground-gun' }
    $campaignStageIndex = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['CampaignStageIndex']) { [int]$script:activeSettings.CampaignStageIndex } else { 0 }
    $campaignBR = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['CampaignBR']) { [double]$script:activeSettings.CampaignBR } else { $minimumBR }
    $currentBRResult = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['CurrentBRResult']) { [string]$script:activeSettings.CurrentBRResult } else { '' }
    $currentChallengeId = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['CurrentChallengeId']) { [string]$script:activeSettings.CurrentChallengeId } else { '' }
    $brRollMode = if ($script:activeSettings -and [string]$script:activeSettings.BRRollMode -eq 'Bracket') { 'Bracket' } else { 'Exact' }
    $domain = if ($script:activeSettings -and $script:activeSettings.PSObject.Properties['Domain']) { Normalize-Domain ([string]$script:activeSettings.Domain) } else { 'Any' }
    @{
        ClearSequenceOnExit = $clearSequenceOnExit
        Domain = $domain
        MinimumBR = $minimumBR
        MaximumBR = $maximumBR
        BRRollMode = $brRollMode
        SessionRollNation = $sessionRollNation
        SessionRollBR = $sessionRollBR
        SessionRollChallenge = $sessionRollChallenge
        SessionRollFunMode = $sessionRollFunMode
        CampaignTrackId = $campaignTrackId
        CampaignStageIndex = $campaignStageIndex
        CampaignBR = $campaignBR
        CurrentBRResult = $currentBRResult
        CurrentChallengeId = $currentChallengeId
    } |
        ConvertTo-Json |
        Set-Content -LiteralPath $script:activePaths.Settings -Encoding UTF8
}

function Get-CampaignBRDisplay {
    if ([string]$script:activeSettings.BRRollMode -eq 'Bracket') {
        $bracket = @(Get-ValidBRBrackets | Where-Object { [double]$_.Minimum -eq [double]$script:activeSettings.CampaignBR } | Select-Object -First 1)
        if ($bracket.Count -gt 0) { return [string]$bracket[0].Label }
    }
    return '{0:N1}' -f [double]$script:activeSettings.CampaignBR
}

function Invoke-CampaignSuccess($challenge, $enabledStages, [bool] $battleRatingWasRolled) {
    $action = $challenge.RewardAction
    $brDisplay = Get-CampaignBRDisplay
    $campaignComplete = $false
    if ($action.Type -eq 'BRSteps' -and [int]$action.Steps -gt 0) {
        if ([string]$script:activeSettings.BRRollMode -eq 'Bracket') {
            $availableBrackets = @(Get-ValidBRBrackets)
            $currentBRIndex = [array]::IndexOf(@($availableBrackets.Minimum), [double]$script:activeSettings.CampaignBR)
            if ($currentBRIndex -lt 0) {
                $nearestBracket = @($availableBrackets | Sort-Object { [math]::Abs($_.Minimum - [double]$script:activeSettings.CampaignBR) })[0]
                $currentBRIndex = [array]::IndexOf(@($availableBrackets.Id), [string]$nearestBracket.Id)
            }
            $campaignComplete = $currentBRIndex -eq $availableBrackets.Count - 1
            $bracketSteps = [math]::Max(1, [math]::Ceiling([int]$action.Steps / 3.0))
            $nextBRIndex = [math]::Min($availableBrackets.Count - 1, $currentBRIndex + $bracketSteps)
            $script:activeSettings.CampaignBR = [double]$availableBrackets[$nextBRIndex].Minimum
            $brDisplay = [string]$availableBrackets[$nextBRIndex].Label
        }
        else {
            $availableBRStages = @($brStages | Where-Object { $_ -ge [double]$script:activeSettings.MinimumBR -and $_ -le [double]$script:activeSettings.MaximumBR })
            $currentBRIndex = [array]::IndexOf($availableBRStages, [double]$script:activeSettings.CampaignBR)
            if ($currentBRIndex -lt 0) {
                $nearestBR = @($availableBRStages | Sort-Object { [math]::Abs($_ - [double]$script:activeSettings.CampaignBR) })[0]
                $currentBRIndex = [array]::IndexOf($availableBRStages, $nearestBR)
            }
            $campaignComplete = $currentBRIndex -eq $availableBRStages.Count - 1
            $nextBRIndex = [math]::Min($availableBRStages.Count - 1, $currentBRIndex + [int]$action.Steps)
            $script:activeSettings.CampaignBR = [double]$availableBRStages[$nextBRIndex]
            $brDisplay = '{0:N1}' -f $script:activeSettings.CampaignBR
        }
        $brResult.Text = $brDisplay
        $script:activeSettings.CurrentBRResult = $brDisplay
    }
    elseif ($action.Type -eq 'TrackSteps' -and [int]$action.Steps -gt 0 -and @($enabledStages).Count -gt 0) {
        $currentStageIndex = [math]::Min([int]$script:activeSettings.CampaignStageIndex, @($enabledStages).Count - 1)
        $campaignComplete = $currentStageIndex -eq @($enabledStages).Count - 1
        $script:activeSettings.CampaignStageIndex = [math]::Min(@($enabledStages).Count - 1, $currentStageIndex + [int]$action.Steps)
    }

    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    $stageLabel = if (@($enabledStages).Count -gt 0) { [string]$enabledStages[[int]$script:activeSettings.CampaignStageIndex].Label } else { 'No enabled stage' }
    $statusMessage = switch ($action.Type) {
        'TrackSteps' { if ($campaignComplete) { "Success recorded - final stage $stageLabel completed!" } else { "Success recorded - advanced to $stageLabel." } }
        'BRSteps' { if ($campaignComplete) { "Success recorded - highest BR $brDisplay completed!" } else { "Success recorded - advanced to BR $brDisplay." } }
        default { 'Success recorded - ready for the next round.' }
    }
    return [pscustomobject]@{
        StageLabel = if ($action.Type -eq 'TrackSteps') { $stageLabel } else { '' }
        BattleRating = if ($battleRatingWasRolled -or $action.Type -eq 'BRSteps') { if ($brDisplay) { $brDisplay } else { '{0:N1}' -f $script:activeSettings.CampaignBR } } else { '' }
        StatusMessage = $statusMessage
        CampaignComplete = $campaignComplete
        CampaignCompleteText = if ($action.Type -eq 'TrackSteps') { "Final stage completed: $stageLabel" } else { "Highest BR completed: $brDisplay" }
    }
}

function Invoke-CampaignFailure($challenge, $enabledStages, [bool] $battleRatingWasRolled) {
    $action = $challenge.FailureAction
    $brDisplay = Get-CampaignBRDisplay
    $statusMessage = 'Failure recorded - stage unchanged.'
    $stageLabel = if (@($enabledStages).Count -gt 0) { [string]$enabledStages[[math]::Min([int]$script:activeSettings.CampaignStageIndex, @($enabledStages).Count - 1)].Label } else { 'No enabled stage' }

    if ($action.Type -eq 'BRStepsDown' -and [int]$action.Steps -gt 0) {
        if ([string]$script:activeSettings.BRRollMode -eq 'Bracket') {
            $availableBrackets = @(Get-ValidBRBrackets)
            $currentBRIndex = [array]::IndexOf(@($availableBrackets.Minimum), [double]$script:activeSettings.CampaignBR)
            if ($currentBRIndex -lt 0) {
                $nearestBracket = @($availableBrackets | Sort-Object { [math]::Abs($_.Minimum - [double]$script:activeSettings.CampaignBR) })[0]
                $currentBRIndex = [array]::IndexOf(@($availableBrackets.Id), [string]$nearestBracket.Id)
            }
            $bracketSteps = [math]::Max(1, [math]::Ceiling([int]$action.Steps / 3.0))
            $nextBRIndex = [math]::Max(0, $currentBRIndex - $bracketSteps)
            $script:activeSettings.CampaignBR = [double]$availableBrackets[$nextBRIndex].Minimum
            $brDisplay = [string]$availableBrackets[$nextBRIndex].Label
        }
        else {
            $availableBRStages = @($brStages | Where-Object { $_ -ge [double]$script:activeSettings.MinimumBR -and $_ -le [double]$script:activeSettings.MaximumBR })
            $currentBRIndex = [array]::IndexOf($availableBRStages, [double]$script:activeSettings.CampaignBR)
            if ($currentBRIndex -lt 0) {
                $nearestBR = @($availableBRStages | Sort-Object { [math]::Abs($_ - [double]$script:activeSettings.CampaignBR) })[0]
                $currentBRIndex = [array]::IndexOf($availableBRStages, $nearestBR)
            }
            $nextBRIndex = [math]::Max(0, $currentBRIndex - [int]$action.Steps)
            $script:activeSettings.CampaignBR = [double]$availableBRStages[$nextBRIndex]
            $brDisplay = '{0:N1}' -f $script:activeSettings.CampaignBR
        }
        $brResult.Text = $brDisplay
        $script:activeSettings.CurrentBRResult = $brDisplay
        $statusMessage = if ($currentBRIndex -eq 0) { "Failure recorded - already at lowest BR $brDisplay." } else { "Failure recorded - dropped to BR $brDisplay." }
    }
    elseif ($action.Type -eq 'TrackStepsDown' -and [int]$action.Steps -gt 0 -and @($enabledStages).Count -gt 0) {
        $currentStageIndex = [math]::Min([int]$script:activeSettings.CampaignStageIndex, @($enabledStages).Count - 1)
        $nextStageIndex = [math]::Max(0, $currentStageIndex - [int]$action.Steps)
        $script:activeSettings.CampaignStageIndex = $nextStageIndex
        $stageLabel = [string]$enabledStages[$nextStageIndex].Label
        $statusMessage = if ($currentStageIndex -eq 0) { "Failure recorded - already at lowest stage $stageLabel." } else { "Failure recorded - dropped to $stageLabel." }
    }

    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    return [pscustomobject]@{
        StageLabel = if ($action.Type -eq 'TrackStepsDown') { $stageLabel } else { '' }
        BattleRating = if ($battleRatingWasRolled -or $action.Type -eq 'BRStepsDown') { if ($brDisplay) { $brDisplay } else { '{0:N1}' -f $script:activeSettings.CampaignBR } } else { '' }
        StatusMessage = $statusMessage
    }
}

function Reset-NationQueue {
    Set-Content -LiteralPath (Get-DomainQueuePath 'Nation') -Value ([string[]]@()) -Encoding UTF8
}

function New-NationQueue {
    $eligible = @(Get-EligibleNations $script:activeSettings.Domain)
    $shuffledNations = @($eligible | Get-Random -Count $eligible.Count)
    Set-Content -LiteralPath (Get-DomainQueuePath 'Nation') -Value $shuffledNations -Encoding UTF8
    return $shuffledNations
}

function Get-NextNation {
    $queue = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'Nation') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -in @(Get-EligibleNations $script:activeSettings.Domain) }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-NationQueue)
    }

    $selectedNation = $queue[0]
    Set-Content -LiteralPath (Get-DomainQueuePath 'Nation') -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return $selectedNation
}

function New-ChallengeQueue {
    $eligible = @(Get-EligibleChallenges)
    $shuffledIds = @($eligible.Id | Get-Random -Count $eligible.Count)
    Set-Content -LiteralPath (Get-DomainQueuePath 'Challenge') -Value $shuffledIds -Encoding UTF8
    return $shuffledIds
}

function Get-NextChallenge {
    $queue = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'Challenge') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -in @(Get-EligibleChallenges).Id }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-ChallengeQueue)
    }

    $selectedId = $queue[0]
    Set-Content -LiteralPath (Get-DomainQueuePath 'Challenge') -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return @($challenges | Where-Object Id -eq $selectedId)[0]
}

function New-FunModeQueue {
    $eligible = @(Get-EligibleFunModes)
    $shuffledIds = @($eligible.Id | Get-Random -Count $eligible.Count)
    Set-Content -LiteralPath (Get-DomainQueuePath 'FunMode') -Value $shuffledIds -Encoding UTF8
    return $shuffledIds
}

function Get-NextFunMode {
    $queue = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'FunMode') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -in @(Get-EligibleFunModes).Id }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-FunModeQueue)
    }

    $selectedId = $queue[0]
    Set-Content -LiteralPath (Get-DomainQueuePath 'FunMode') -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return @($funModes | Where-Object Id -eq $selectedId)[0]
}

function New-BitmapImage([string] $path) {
    $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [Uri]::new($path, [UriKind]::Absolute)
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

function Reset-BRQueue {
    Set-Content -LiteralPath $script:activePaths.BRQueue -Value ([string[]]@()) -Encoding UTF8
    Set-Content -LiteralPath $script:activePaths.BRBracketQueue -Value ([string[]]@()) -Encoding UTF8
}

function New-BRQueue {
    $validStages = @($brStages | Where-Object {
        $_ -ge [double]$script:activeSettings.MinimumBR -and
        $_ -le [double]$script:activeSettings.MaximumBR
    })
    $shuffledStages = @($validStages | Get-Random -Count $validStages.Count)
    $lines = @($shuffledStages | ForEach-Object { $_.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) })
    Set-Content -LiteralPath $script:activePaths.BRQueue -Value $lines -Encoding UTF8
    return $shuffledStages
}

function Get-NextBR {
    $validStages = @($brStages | Where-Object {
        $_ -ge [double]$script:activeSettings.MinimumBR -and
        $_ -le [double]$script:activeSettings.MaximumBR
    })
    $queue = @(
        foreach ($line in @(Get-Content -LiteralPath $script:activePaths.BRQueue)) {
            $value = 0.0
            if ([double]::TryParse($line, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -in $validStages) {
                [double]$value
            }
        }
    )
    if ($queue.Count -eq 0) { $queue = @(New-BRQueue) }
    $selected = [double]$queue[0]
    $remainingLines = @($queue | Select-Object -Skip 1 | ForEach-Object { $_.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) })
    Set-Content -LiteralPath $script:activePaths.BRQueue -Value $remainingLines -Encoding UTF8
    return $selected
}

function Get-ValidBRBrackets {
    $validStages = @($brStages | Where-Object {
        $_ -ge [double]$script:activeSettings.MinimumBR -and
        $_ -le [double]$script:activeSettings.MaximumBR
    })
    return @($validStages | Group-Object { [math]::Floor([double]$_) } | ForEach-Object {
        $stages = @($_.Group | Sort-Object)
        [pscustomobject]@{
            Id = $stages[0].ToString('0.0', [Globalization.CultureInfo]::InvariantCulture) + ':' + $stages[-1].ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
            Minimum = [double]$stages[0]
            Maximum = [double]$stages[-1]
            Label = ('{0:N1}-{1:N1}' -f [double]$stages[0], [double]$stages[-1])
        }
    })
}

function New-BRBracketQueue {
    $validBrackets = @(Get-ValidBRBrackets)
    $shuffledIds = @($validBrackets.Id | Get-Random -Count $validBrackets.Count)
    Set-Content -LiteralPath $script:activePaths.BRBracketQueue -Value $shuffledIds -Encoding UTF8
    return $shuffledIds
}

function Get-NextBRBracket {
    $validBrackets = @(Get-ValidBRBrackets)
    $validIds = @($validBrackets.Id)
    $queue = @(Get-Content -LiteralPath $script:activePaths.BRBracketQueue | Where-Object { $_ -in $validIds })
    if ($queue.Count -eq 0) { $queue = @(New-BRBracketQueue) }
    $selectedId = [string]$queue[0]
    Set-Content -LiteralPath $script:activePaths.BRBracketQueue -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return @($validBrackets | Where-Object Id -eq $selectedId)[0]
}

function Show-ChallengeEditor($owner, $existingChallenge) {
    [xml]$editorXaml = Get-Content -LiteralPath $challengeEditorXamlFile -Raw
    $editorReader = [System.Xml.XmlNodeReader]::new($editorXaml)
    $editor = [Windows.Markup.XamlReader]::Load($editorReader)
    $editor.Owner = $owner

    $nameBox = $editor.FindName('ChallengeEditorName')
    $objectiveBox = $editor.FindName('ChallengeEditorObjective')
    $domainBox = $editor.FindName('ChallengeEditorDomain')
    $trackerList = $editor.FindName('ChallengeEditorTrackers')
    $recordingMode = $editor.FindName('ChallengeEditorRecordingMode')
    $rewardType = $editor.FindName('ChallengeEditorRewardType')
    $failureType = $editor.FindName('ChallengeEditorFailureType')
    $rewardText = $editor.FindName('ChallengeEditorRewardText')
    $addCounter = $editor.FindName('AddCounterTrackerButton')
    $addCheckbox = $editor.FindName('AddCheckboxTrackerButton')
    $editTracker = $editor.FindName('EditTrackerButton')
    $deleteTracker = $editor.FindName('DeleteTrackerButton')
    $saveButton = $editor.FindName('ChallengeEditorSaveButton')
    $cancelButton = $editor.FindName('ChallengeEditorCancelButton')

    $rewardOptions = @(
        [pscustomobject]@{ Id='None:0'; Name='No automatic advancement'; Type='None'; Steps=0; DefaultText='Complete the challenge.' }
        [pscustomobject]@{ Id='BRSteps:1'; Name='Advance BR by one stage (+0.3/+0.4)'; Type='BRSteps'; Steps=1; DefaultText='Advance one BR stage.' }
        [pscustomobject]@{ Id='BRSteps:3'; Name='Advance BR by +1.0'; Type='BRSteps'; Steps=3; DefaultText='Advance BR by 1.0.' }
        [pscustomobject]@{ Id='TrackSteps:1'; Name='Advance current weapon track'; Type='TrackSteps'; Steps=1; DefaultText='Advance one weapon stage.' }
    )
    $domainBox.ItemsSource = $domains
    $rewardType.ItemsSource = $rewardOptions
    $failureOptions = @(
        [pscustomobject]@{ Id='None:0'; Name='Stay at current stage'; Type='None'; Steps=0 }
        [pscustomobject]@{ Id='BRStepsDown:1'; Name='Go down one exact BR stage / one whole bracket'; Type='BRStepsDown'; Steps=1 }
        [pscustomobject]@{ Id='BRStepsDown:3'; Name='Go down by 1.0 / one whole bracket'; Type='BRStepsDown'; Steps=3 }
        [pscustomobject]@{ Id='TrackStepsDown:1'; Name='Go down one weapon stage'; Type='TrackStepsDown'; Steps=1 }
    )
    $recordingMode.ItemsSource = @(
        [pscustomobject]@{ Id='Detailed'; Name='Detailed trackers' }
        [pscustomobject]@{ Id='Simple'; Name='Simple success / failed' }
    )
    $trackers = [Collections.ArrayList]::new()

    $refreshFailureOptions = {
        param([string] $preferredValue)
        $rewardActionType = if ($rewardType.SelectedItem) { [string]$rewardType.SelectedItem.Type } else { 'None' }
        $allowedIds = switch ($rewardActionType) {
            'BRSteps' {
                if ([int]$rewardType.SelectedItem.Steps -ge 3) { @('None:0','BRStepsDown:3') }
                else { @('None:0','BRStepsDown:1') }
            }
            'TrackSteps' { @('None:0','TrackStepsDown:1') }
            default { @('None:0') }
        }
        if ($rewardActionType -eq 'BRSteps' -and [int]$rewardType.SelectedItem.Steps -ge 3 -and $preferredValue -eq 'BRStepsDown:1') {
            $preferredValue = 'BRStepsDown:3'
        }
        $failureType.ItemsSource = @($failureOptions | Where-Object { $_.Id -in $allowedIds })
        $failureType.SelectedValue = $preferredValue
        if (-not $failureType.SelectedValue) { $failureType.SelectedValue = 'None:0' }
    }

    $refreshTrackers = {
        param([string] $selectedId)
        foreach ($tracker in @($trackers)) {
            $summary = if ($tracker.Type -eq 'Counter') { "$($tracker.Label) (target $($tracker.Target))" } else { "$($tracker.Label) (checkbox)" }
            $tracker | Add-Member -NotePropertyName Summary -NotePropertyValue $summary -Force
        }
        $trackerList.ItemsSource = $null
        $trackerList.ItemsSource = @($trackers)
        if ($selectedId) { $trackerList.SelectedItem = @($trackers | Where-Object Id -eq $selectedId)[0] }
    }

    if ($existingChallenge) {
        $challenge = ConvertTo-Challenge $existingChallenge
        $nameBox.Text = $challenge.Name
        $objectiveBox.Text = $challenge.Objective
        $rewardText.Text = $challenge.Reward
        foreach ($tracker in $challenge.Trackers) { [void]$trackers.Add($tracker) }
        $rewardType.SelectedValue = "$($challenge.RewardAction.Type):$($challenge.RewardAction.Steps)"
        & $refreshFailureOptions "$($challenge.FailureAction.Type):$($challenge.FailureAction.Steps)"
        $recordingMode.SelectedValue = $challenge.RecordingMode
        $domainBox.SelectedValue = $challenge.Domain
    }
    else {
        $rewardType.SelectedValue = 'None:0'
        & $refreshFailureOptions 'None:0'
        $recordingMode.SelectedValue = 'Detailed'
        $domainBox.SelectedValue = 'Any'
        $rewardText.Text = 'Complete the challenge.'
        [void]$trackers.Add([pscustomobject]@{ Id=[guid]::NewGuid().ToString('N'); Label='Objective completed'; Type='Checkbox'; Target=1; Required=$true })
    }
    if (-not $rewardType.SelectedValue) { $rewardType.SelectedIndex = 0 }
    if (-not $failureType.SelectedValue) { & $refreshFailureOptions 'None:0' }
    if (-not $recordingMode.SelectedValue) { $recordingMode.SelectedValue = 'Detailed' }
    if (-not $domainBox.SelectedValue) { $domainBox.SelectedValue = 'Any' }
    & $refreshTrackers $null

    $rewardType.Add_SelectionChanged({
        $option = $rewardType.SelectedItem
        & $refreshFailureOptions 'None:0'
        if ($option -and ([string]::IsNullOrWhiteSpace($rewardText.Text) -or $rewardOptions.DefaultText -contains $rewardText.Text)) {
            $rewardText.Text = $option.DefaultText
        }
    })

    $addCounter.Add_Click({
        $label = [Microsoft.VisualBasic.Interaction]::InputBox('Counter label:', 'Add session counter', '').Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { return }
        $targetText = [Microsoft.VisualBasic.Interaction]::InputBox('Required target:', 'Add session counter', '1').Trim()
        $target = 0
        if (-not [int]::TryParse($targetText, [ref]$target) -or $target -lt 1) { return }
        $tracker = [pscustomobject]@{ Id=[guid]::NewGuid().ToString('N'); Label=$label; Type='Counter'; Target=$target; Required=$true }
        [void]$trackers.Add($tracker); & $refreshTrackers $tracker.Id
    })
    $addCheckbox.Add_Click({
        $label = [Microsoft.VisualBasic.Interaction]::InputBox('Checkbox label:', 'Add session checkbox', '').Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { return }
        $tracker = [pscustomobject]@{ Id=[guid]::NewGuid().ToString('N'); Label=$label; Type='Checkbox'; Target=1; Required=$true }
        [void]$trackers.Add($tracker); & $refreshTrackers $tracker.Id
    })
    $editTracker.Add_Click({
        $tracker = $trackerList.SelectedItem
        if (-not $tracker) { return }
        $label = [Microsoft.VisualBasic.Interaction]::InputBox('Tracker label:', 'Edit session tracker', $tracker.Label).Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { return }
        $tracker.Label = $label
        if ($tracker.Type -eq 'Counter') {
            $targetText = [Microsoft.VisualBasic.Interaction]::InputBox('Required target:', 'Edit session counter', [string]$tracker.Target).Trim()
            $target = 0
            if (-not [int]::TryParse($targetText, [ref]$target) -or $target -lt 1) { return }
            $tracker.Target = $target
        }
        & $refreshTrackers $tracker.Id
    })
    $deleteTracker.Add_Click({
        $tracker = $trackerList.SelectedItem
        if (-not $tracker -or $trackers.Count -le 1) { return }
        [void]$trackers.Remove($tracker); & $refreshTrackers $null
    })
    $cancelButton.Add_Click({ $editor.DialogResult = $false })
    $saveButton.Add_Click({
        $name = $nameBox.Text.Trim(); $objective = $objectiveBox.Text.Trim(); $reward = $rewardText.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($objective) -or [string]::IsNullOrWhiteSpace($reward) -or $trackers.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Name, objective, reward, and at least one tracker are required.', 'Thunder Roulette') | Out-Null
            return
        }
        $option = $rewardType.SelectedItem
        $failureOption = $failureType.SelectedItem
        $editor.Tag = [pscustomobject]@{
            Id = if ($existingChallenge) { [string]$existingChallenge.Id } else { 'custom-' + [guid]::NewGuid().ToString('N') }
            Name=$name; Domain=[string]$domainBox.SelectedValue; Objective=$objective; Reward=$reward; Trackers=@($trackers)
            RecordingMode=[string]$recordingMode.SelectedValue
            RewardAction=[pscustomobject]@{Type=$option.Type;Steps=$option.Steps}
            FailureAction=[pscustomobject]@{Type=$failureOption.Type;Steps=$failureOption.Steps}
        }
        $editor.DialogResult = $true
    })

    if ($editor.ShowDialog()) { return ConvertTo-Challenge $editor.Tag }
    return $null
}

function Show-SessionWindow($owner, $challenge, [string] $nation, [string] $battleRating, [string] $funMode, $track, $stage, [scriptblock] $advanceSuccess, [scriptblock] $applyFailure) {
    [xml]$sessionXaml = Get-Content -LiteralPath $sessionXamlFile -Raw
    $sessionReader = [System.Xml.XmlNodeReader]::new($sessionXaml)
    $session = [Windows.Markup.XamlReader]::Load($sessionReader)
    $session.Owner = $owner

    $session.FindName('SessionChallengeName').Text = $challenge.Name
    $session.FindName('SessionObjective').Text = $challenge.Objective
    $session.FindName('SessionNation').Text = "Nation: $nation"
    $sessionBRText = $session.FindName('SessionBR')
    if ([string]::IsNullOrWhiteSpace($battleRating)) {
        $sessionBRText.Visibility = [Windows.Visibility]::Collapsed
    }
    else {
        $sessionBRText.Text = "Battle rating: $battleRating"
    }
    $session.FindName('SessionFunMode').Text = "Fun mode: $funMode"
    $sessionTrackText = $session.FindName('SessionTrack')
    $sessionStageText = $session.FindName('SessionStage')
    if ($challenge.RewardAction.Type -eq 'TrackSteps' -or $challenge.FailureAction.Type -eq 'TrackStepsDown') {
        $sessionTrackText.Text = "Campaign: $($track.Name)"
        $sessionStageText.Text = if ($stage) { $stage.Label } else { 'No enabled stage' }
    }
    else {
        $sessionTrackText.Visibility = [Windows.Visibility]::Collapsed
        $sessionStageText.Visibility = [Windows.Visibility]::Collapsed
    }
    $session.FindName('SessionReward').Text = "Success: $($challenge.Reward)"

    $trackerPanel = $session.FindName('SessionTrackerPanel')
    $trackerScroll = $session.FindName('SessionTrackerScroll')
    $successButton = $session.FindName('SessionSuccessButton')
    $failedButton = $session.FindName('SessionFailedButton')
    $abandonButton = $session.FindName('SessionAbandonButton')
    $completionHint = $session.FindName('SessionCompletionHint')
    $timerText = $session.FindName('SessionTimer')
    $notes = $session.FindName('SessionNotes')
    $campaignCompleteBanner = $session.FindName('SessionCampaignCompleteBanner')
    $campaignCompleteText = $session.FindName('SessionCampaignCompleteText')
    $values = @{}
    $counterTexts = @{}
    $checkboxes = @{}
    $detailedRecording = [string]$challenge.RecordingMode -ne 'Simple'
    $recordsBRProgression = $challenge.RewardAction.Type -eq 'BRSteps' -or $challenge.FailureAction.Type -eq 'BRStepsDown'
    $recordsTrackProgression = $challenge.RewardAction.Type -eq 'TrackSteps' -or $challenge.FailureAction.Type -eq 'TrackStepsDown'
    $sessionState = [pscustomobject]@{
        SuccessCount = 0
        FailureCount = 0
        AttemptNotes = [Collections.ArrayList]::new()
        Attempts = [Collections.ArrayList]::new()
    }
    foreach ($tracker in @($challenge.Trackers)) { $values[$tracker.Id] = if ($tracker.Type -eq 'Counter') { 0 } else { $false } }

    $updateCompletion = {
        if (-not $detailedRecording) {
            $successButton.IsEnabled = $true
            $completionHint.Text = 'Record Success or Failed when the attempt is resolved.'
            $completionHint.Foreground = [Windows.Media.Brushes]::LightSlateGray
            return
        }
        $complete = $true
        foreach ($tracker in @($challenge.Trackers | Where-Object Required)) {
            if ($tracker.Type -eq 'Counter' -and [int]$values[$tracker.Id] -lt [int]$tracker.Target) { $complete = $false; break }
            if ($tracker.Type -eq 'Checkbox' -and -not [bool]$values[$tracker.Id]) { $complete = $false; break }
        }
        $successButton.IsEnabled = $complete
        $completionHint.Text = if ($complete) { 'All required objectives complete.' } else { 'Complete all required objectives to mark success.' }
        $completionHint.Foreground = if ($complete) { [Windows.Media.Brushes]::LightGreen } else { [Windows.Media.Brushes]::LightSlateGray }
    }

    if (-not $detailedRecording) { $trackerScroll.Visibility = [Windows.Visibility]::Collapsed }
    foreach ($tracker in @($challenge.Trackers | Where-Object { $detailedRecording })) {
        $row = [Windows.Controls.Border]::new()
        $row.Background = [Windows.Media.Brushes]::WhiteSmoke
        $row.CornerRadius = [Windows.CornerRadius]::new(8)
        $row.Padding = [Windows.Thickness]::new(12)
        $row.Margin = [Windows.Thickness]::new(0,0,0,8)
        $grid = [Windows.Controls.Grid]::new()
        $grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::new(1,[Windows.GridUnitType]::Star) })
        $grid.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]@{ Width = [Windows.GridLength]::Auto })
        $label = [Windows.Controls.TextBlock]@{ Text=$tracker.Label; FontSize=15; VerticalAlignment='Center'; Foreground=[Windows.Media.Brushes]::Black }
        $grid.Children.Add($label) | Out-Null

        if ($tracker.Type -eq 'Counter') {
            $controls = [Windows.Controls.StackPanel]@{ Orientation='Horizontal' }
            [Windows.Controls.Grid]::SetColumn($controls, 1)
            $minus = [Windows.Controls.Button]@{ Content='-'; Width=32; Height=28 }
            $valueText = [Windows.Controls.TextBlock]@{ Text="0 / $($tracker.Target)"; Width=70; TextAlignment='Center'; VerticalAlignment='Center'; FontWeight='Bold'; Foreground=[Windows.Media.Brushes]::Black }
            $plus = [Windows.Controls.Button]@{ Content='+'; Width=32; Height=28 }
            $controls.Children.Add($minus) | Out-Null; $controls.Children.Add($valueText) | Out-Null; $controls.Children.Add($plus) | Out-Null
            $grid.Children.Add($controls) | Out-Null
            $trackerId = [string]$tracker.Id; $target = [int]$tracker.Target; $counterText = $valueText
            $counterTexts[$trackerId] = $valueText
            $minus.Add_Click(({ $values[$trackerId] = [math]::Max(0, [int]$values[$trackerId] - 1); $counterText.Text = "$($values[$trackerId]) / $target"; & $updateCompletion }).GetNewClosure())
            $plus.Add_Click(({ $values[$trackerId] = [int]$values[$trackerId] + 1; $counterText.Text = "$($values[$trackerId]) / $target"; & $updateCompletion }).GetNewClosure())
        }
        else {
            $check = [Windows.Controls.CheckBox]@{ VerticalAlignment='Center'; HorizontalAlignment='Center' }
            [Windows.Controls.Grid]::SetColumn($check, 1)
            $grid.Children.Add($check) | Out-Null
            $trackerId = [string]$tracker.Id
            $checkboxes[$trackerId] = $check
            $check.Add_Checked(({ $values[$trackerId] = $true; & $updateCompletion }).GetNewClosure())
            $check.Add_Unchecked(({ $values[$trackerId] = $false; & $updateCompletion }).GetNewClosure())
        }
        $row.Child = $grid
        $trackerPanel.Children.Add($row) | Out-Null
    }

    $startedAt = Get-Date
    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({ $elapsed = (Get-Date) - $startedAt; $timerText.Text = '{0:00}:{1:00}' -f [math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds })
    $timer.Start()
    & $updateCompletion

    $getVisibleBR = {
        if ($sessionBRText.Visibility -eq [Windows.Visibility]::Collapsed) { return $null }
        return ([string]$sessionBRText.Text -replace '^Battle rating:\s*', '')
    }
    $getVisibleStage = {
        if ($sessionStageText.Visibility -eq [Windows.Visibility]::Collapsed) { return $null }
        return [string]$sessionStageText.Text
    }
    $snapshotTrackers = {
        if (-not $detailedRecording) { return @() }
        return @($challenge.Trackers | ForEach-Object {
            [pscustomobject]@{
                Id=[string]$_.Id; Label=[string]$_.Label; Type=[string]$_.Type
                Value=$values[$_.Id]; Target=[int]$_.Target; Required=[bool]$_.Required
            }
        })
    }
    $completeBanner = $campaignCompleteBanner
    $completeText = $campaignCompleteText
    $showCampaignComplete = {
        param([string] $message)
        if (-not $completeBanner -or -not $completeText) { return }
        $completeText.Text = $message
        $completeBanner.Visibility = [Windows.Visibility]::Visible
        $completeBanner.Opacity = 0
        $scale = [Windows.Media.ScaleTransform]$completeBanner.RenderTransform
        if (-not $scale) { return }
        $scale.ScaleX = 0.85; $scale.ScaleY = 0.85
        $fadeSequence = [Windows.Media.Animation.DoubleAnimationUsingKeyFrames]::new()
        foreach ($frame in @(
            [pscustomobject]@{ Value=0.0; Milliseconds=0 }
            [pscustomobject]@{ Value=1.0; Milliseconds=240 }
            [pscustomobject]@{ Value=1.0; Milliseconds=2400 }
            [pscustomobject]@{ Value=0.0; Milliseconds=2900 }
        )) {
            $keyFrame = [Windows.Media.Animation.LinearDoubleKeyFrame]::new()
            $keyFrame.Value = [double]$frame.Value
            $keyFrame.KeyTime = [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds($frame.Milliseconds))
            [void]$fadeSequence.KeyFrames.Add($keyFrame)
        }
        $growX = [Windows.Media.Animation.DoubleAnimation]::new(0.85, 1, [TimeSpan]::FromMilliseconds(300))
        $growY = [Windows.Media.Animation.DoubleAnimation]::new(0.85, 1, [TimeSpan]::FromMilliseconds(300))
        $completeBanner.BeginAnimation([Windows.UIElement]::OpacityProperty, $fadeSequence)
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $growX)
        $scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $growY)
    }.GetNewClosure()

    $finishSession = {
        param([string] $outcome)
        if (-not [string]::IsNullOrWhiteSpace($notes.Text)) {
            [void]$sessionState.AttemptNotes.Add("Session: $($notes.Text.Trim())")
            $notes.Text = ''
        }
        $session.Tag = [pscustomobject]@{
            Outcome=$outcome; StartedAt=$startedAt.ToString('o'); EndedAt=(Get-Date).ToString('o')
            DurationSeconds=[int]((Get-Date)-$startedAt).TotalSeconds
            Notes=[string]::Join([Environment]::NewLine, @($sessionState.AttemptNotes))
            SuccessCount=[int]$sessionState.SuccessCount; FailureCount=[int]$sessionState.FailureCount
            TrackerValues=@($challenge.Trackers | ForEach-Object { [pscustomobject]@{Id=$_.Id;Label=$_.Label;Value=$values[$_.Id];Target=$_.Target} })
            Attempts=@($sessionState.Attempts)
        }
        $session.Close()
    }
    $successButton.Add_Click({
        $sessionState.SuccessCount = [int]$sessionState.SuccessCount + 1
        $attemptNote = $notes.Text.Trim()
        $beforeBR = if ($recordsBRProgression) { & $getVisibleBR } else { $null }
        $beforeStage = if ($recordsTrackProgression) { & $getVisibleStage } else { $null }
        $attemptTrackers = @(& $snapshotTrackers)
        if (-not [string]::IsNullOrWhiteSpace($attemptNote)) {
            [void]$sessionState.AttemptNotes.Add("Success $($sessionState.SuccessCount): $attemptNote")
        }
        $notes.Text = ''
        $newState = & $advanceSuccess
        $advancedStageLabel = $null
        $successStatusMessage = 'Success recorded - ready for the next round.'
        if ($newState) {
            if ($newState.PSObject.Properties['StageLabel']) {
                $advancedStageLabel = [string]$newState.StageLabel
                $sessionStageText.Text = $advancedStageLabel
            }
            if ($newState.PSObject.Properties['BattleRating'] -and -not [string]::IsNullOrWhiteSpace([string]$newState.BattleRating)) {
                $sessionBRText.Text = "Battle rating: $($newState.BattleRating)"
            }
            if ($newState.PSObject.Properties['StatusMessage']) { $successStatusMessage = [string]$newState.StatusMessage }
            if ($newState.PSObject.Properties['CampaignComplete'] -and [bool]$newState.CampaignComplete) {
                & $showCampaignComplete ([string]$newState.CampaignCompleteText)
            }
        }
        [void]$sessionState.Attempts.Add([pscustomobject]@{
            Number=$sessionState.Attempts.Count + 1; Outcome='Success'; RecordedAt=(Get-Date).ToString('o')
            Notes=$attemptNote; TrackerValues=$attemptTrackers
            StartingBR=$beforeBR; EndingBR=$(if ($recordsBRProgression) { & $getVisibleBR } else { $null })
            StartingStage=$beforeStage; EndingStage=$(if ($recordsTrackProgression) { & $getVisibleStage } else { $null })
            StatusMessage=$successStatusMessage
        })
        foreach ($tracker in @($challenge.Trackers)) {
            $values[$tracker.Id] = if ($tracker.Type -eq 'Counter') { 0 } else { $false }
            if ($tracker.Type -eq 'Counter' -and $counterTexts.ContainsKey($tracker.Id)) { $counterTexts[$tracker.Id].Text = "0 / $($tracker.Target)" }
            if ($tracker.Type -eq 'Checkbox' -and $checkboxes.ContainsKey($tracker.Id)) { $checkboxes[$tracker.Id].IsChecked = $false }
        }
        & $updateCompletion
        <#
        $completionHint.Text = if ($advancedStageLabel) { "Success recorded — advanced to $advancedStageLabel." } else { 'Success recorded — ready for the next round.' }
        #>
        $completionHint.Text = $successStatusMessage
        $completionHint.Foreground = [Windows.Media.Brushes]::LightGreen
    })
    $failedButton.Add_Click({
        $sessionState.FailureCount = [int]$sessionState.FailureCount + 1
        $attemptNote = $notes.Text.Trim()
        $beforeBR = if ($recordsBRProgression) { & $getVisibleBR } else { $null }
        $beforeStage = if ($recordsTrackProgression) { & $getVisibleStage } else { $null }
        $attemptTrackers = @(& $snapshotTrackers)
        if (-not [string]::IsNullOrWhiteSpace($attemptNote)) {
            [void]$sessionState.AttemptNotes.Add("Failed $($sessionState.FailureCount): $attemptNote")
        }
        $notes.Text = ''
        $failureState = & $applyFailure
        $failureStatusMessage = 'Failure recorded - stage unchanged.'
        if ($failureState) {
            if ($failureState.PSObject.Properties['StageLabel'] -and -not [string]::IsNullOrWhiteSpace([string]$failureState.StageLabel)) {
                $sessionStageText.Text = [string]$failureState.StageLabel
            }
            if ($failureState.PSObject.Properties['BattleRating'] -and -not [string]::IsNullOrWhiteSpace([string]$failureState.BattleRating)) {
                $sessionBRText.Text = "Battle rating: $($failureState.BattleRating)"
            }
            if ($failureState.PSObject.Properties['StatusMessage']) { $failureStatusMessage = [string]$failureState.StatusMessage }
        }
        [void]$sessionState.Attempts.Add([pscustomobject]@{
            Number=$sessionState.Attempts.Count + 1; Outcome='Failed'; RecordedAt=(Get-Date).ToString('o')
            Notes=$attemptNote; TrackerValues=$attemptTrackers
            StartingBR=$beforeBR; EndingBR=$(if ($recordsBRProgression) { & $getVisibleBR } else { $null })
            StartingStage=$beforeStage; EndingStage=$(if ($recordsTrackProgression) { & $getVisibleStage } else { $null })
            StatusMessage=$failureStatusMessage
        })
        foreach ($tracker in @($challenge.Trackers)) {
            $values[$tracker.Id] = if ($tracker.Type -eq 'Counter') { 0 } else { $false }
            if ($tracker.Type -eq 'Counter' -and $counterTexts.ContainsKey($tracker.Id)) { $counterTexts[$tracker.Id].Text = "0 / $($tracker.Target)" }
            if ($tracker.Type -eq 'Checkbox' -and $checkboxes.ContainsKey($tracker.Id)) { $checkboxes[$tracker.Id].IsChecked = $false }
        }
        & $updateCompletion
        $completionHint.Text = $failureStatusMessage
        $completionHint.Foreground = [Windows.Media.Brushes]::LightCoral
    })
    $abandonButton.Add_Click({
        $outcome = if ([int]$sessionState.SuccessCount -gt 0) { 'Completed' } elseif ([int]$sessionState.FailureCount -gt 0) { 'Failed' } else { 'Abandoned' }
        & $finishSession $outcome
    })

    $null = $session.ShowDialog()
    $timer.Stop()
    if ($session.Tag) { return $session.Tag }
    $remainingNotes = @($sessionState.AttemptNotes)
    if (-not [string]::IsNullOrWhiteSpace($notes.Text)) { $remainingNotes += "Session: $($notes.Text.Trim())" }
    return [pscustomobject]@{
        Outcome=$(if ([int]$sessionState.SuccessCount -gt 0) { 'Completed' } elseif ([int]$sessionState.FailureCount -gt 0) { 'Failed' } else { 'Abandoned' })
        StartedAt=$startedAt.ToString('o'); EndedAt=(Get-Date).ToString('o'); DurationSeconds=[int]((Get-Date)-$startedAt).TotalSeconds
        Notes=[string]::Join([Environment]::NewLine, $remainingNotes); SuccessCount=[int]$sessionState.SuccessCount
        FailureCount=[int]$sessionState.FailureCount; TrackerValues=@(); Attempts=@($sessionState.Attempts)
    }
}

Initialize-AppData
Load-DomainSettings
Load-ContentLibraries
Load-ProgressionCatalog

[xml]$xaml = Get-Content -LiteralPath $xamlFile -Raw
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$profileSelector = $window.FindName('ProfileSelector')
$domainSelector = $window.FindName('DomainSelector')
$manageButton = $window.FindName('ManageButton')
$resetAllButton = $window.FindName('ResetAllButton')
$rollButton = $window.FindName('RollButton')
$rollSessionButton = $window.FindName('RollSessionButton')
$startSessionButton = $window.FindName('StartSessionButton')
$resetButton = $window.FindName('ResetButton')
$nationName = $window.FindName('NationName')
$nationImage = $window.FindName('NationImage')
$remainingText = $window.FindName('RemainingText')
$rollBRButton = $window.FindName('RollBRButton')
$brResult = $window.FindName('BRResult')
$brRangeText = $window.FindName('BRRangeText')
$rollChallengeButton = $window.FindName('RollChallengeButton')
$challengeName = $window.FindName('ChallengeName')
$challengeObjective = $window.FindName('ChallengeObjective')
$challengeReward = $window.FindName('ChallengeReward')
$challengeRemainingText = $window.FindName('ChallengeRemainingText')
$rollFunModeButton = $window.FindName('RollFunModeButton')
$funModeName = $window.FindName('FunModeName')
$funModeRule = $window.FindName('FunModeRule')
$funModeRemainingText = $window.FindName('FunModeRemainingText')
$script:currentChallenge = $null

$updateRollSessionAvailability = {
    $enabledCount = @(
        $script:activeSettings.SessionRollNation,
        $script:activeSettings.SessionRollBR,
        $script:activeSettings.SessionRollChallenge,
        $script:activeSettings.SessionRollFunMode
    ) | Where-Object { $_ }
    $rollSessionButton.IsEnabled = @($enabledCount).Count -gt 0
}

$backgroundPath = Join-Path $appRoot 'Assets\Thunder-Roulette-Background.png'
$window.Background = [System.Windows.Media.ImageBrush]@{
    ImageSource = New-BitmapImage $backgroundPath
    Stretch = [System.Windows.Media.Stretch]::UniformToFill
    Opacity = 0.42
}
$emptyImagePath = Join-Path $appRoot 'Assets\NationIcons\No-Nation.png'
$nationImage.Source = New-BitmapImage $emptyImagePath

$updateRemainingText = {
    $remaining = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'Nation') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count
    $remainingText.Text = if ($remaining -eq 0) {
        'A fresh sequence will begin on the next roll'
    }
    else {
        "$remaining nation$(if ($remaining -ne 1) { 's' }) left in this sequence"
    }
}

$updateChallengeRemainingText = {
    $remaining = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'Challenge') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count
    $challengeRemainingText.Text = if ($remaining -eq 0) {
        'A fresh challenge deck will begin on the next draw'
    }
    else {
        "$remaining challenge$(if ($remaining -ne 1) { 's' }) left in this deck"
    }
}

$updateFunModeRemainingText = {
    $remaining = @(
        Get-Content -LiteralPath (Get-DomainQueuePath 'FunMode') |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count
    $funModeRemainingText.Text = if ($remaining -eq 0) {
        'A fresh fun-mode deck will begin on the next draw'
    }
    else {
        "$remaining mode$(if ($remaining -ne 1) { 's' }) left in this deck"
    }
}

$clearCurrentChallenge = {
    $script:currentChallenge = $null
    $script:activeSettings.CurrentChallengeId = ''
    $challengeName.Text = 'No challenge drawn'
    $challengeObjective.Text = 'Draw a challenge when your squad is feeling brave.'
    $challengeReward.Text = ''
    $startSessionButton.IsEnabled = $false
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
}

$refreshCurrentChallengeFromLibrary = {
    if (-not $script:currentChallenge) { return }
    $updatedChallenge = @($script:challenges | Where-Object { $_.Id -eq [string]$script:currentChallenge.Id } | Select-Object -First 1)
    if ($updatedChallenge.Count -eq 0) {
        & $clearCurrentChallenge
        return
    }
    $script:currentChallenge = $updatedChallenge[0]
    $script:activeSettings.CurrentChallengeId = [string]$script:currentChallenge.Id
    $challengeName.Text = $script:currentChallenge.Name
    $challengeObjective.Text = $script:currentChallenge.Objective
    $challengeReward.Text = "SUCCESS: $($script:currentChallenge.Reward)"
    $startSessionButton.IsEnabled = $true
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
}

$clearCurrentFunMode = {
    $funModeName.Text = 'No fun mode drawn'
    $funModeRule.Text = 'Draw a lineup constraint for additional questionable decisions.'
}

$applyDomain = {
    param([string] $domain, [bool] $save = $true)
    $domain = Normalize-Domain $domain
    $script:activeSettings.Domain = $domain
    $eligibleTracks = @(Get-EligibleProgressionTracks $domain)
    if ($eligibleTracks.Count -gt 0 -and [string]$script:activeSettings.CampaignTrackId -notin @($eligibleTracks.Id)) {
        $script:activeSettings.CampaignTrackId = [string]$eligibleTracks[0].Id
        $script:activeSettings.CampaignStageIndex = 0
    }
    if ($script:currentChallenge -and -not (Test-ContentDomain $script:currentChallenge $domain)) { & $clearCurrentChallenge }
    & $clearCurrentFunMode
    $nationName.Text = 'Ready?'
    $nationImage.Source = New-BitmapImage $emptyImagePath
    & $updateRemainingText
    & $updateChallengeRemainingText
    & $updateFunModeRemainingText
    if ($save) { Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR) }
}

$setActiveProfile = {
    param([string] $profileId)

    if ($script:activeProfileId -and $script:activePaths) {
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    }

    $script:activeProfileId = $profileId
    $script:activePaths = Get-ProfilePaths $profileId
    $script:profileStore.LastProfileId = $profileId
    Save-ProfileStore

    $script:activeSettings = Get-ProfileSettings
    $script:domainChanging = $true
    $domainSelector.SelectedValue = [string]$script:activeSettings.Domain
    $script:domainChanging = $false
    & $applyDomain ([string]$script:activeSettings.Domain) $false
    $campaignTrack = @($script:progressionCatalog.Tracks | Where-Object { $_.Id -eq $script:activeSettings.CampaignTrackId } | Select-Object -First 1)
    if ($campaignTrack.Count -eq 0) {
        $script:activeSettings.CampaignTrackId = 'ground-gun'
        $campaignTrack = @($script:progressionCatalog.Tracks | Where-Object Id -eq 'ground-gun')
    }
    $enabledCampaignStages = @($campaignTrack[0].Stages | Where-Object Enabled)
    $script:activeSettings.CampaignStageIndex = if ($enabledCampaignStages.Count -eq 0) { 0 } else { [math]::Min([int]$script:activeSettings.CampaignStageIndex, $enabledCampaignStages.Count - 1) }
    $script:activeSettings.CampaignBR = [math]::Max([double]$script:activeSettings.MinimumBR, [math]::Min([double]$script:activeSettings.CampaignBR, [double]$script:activeSettings.MaximumBR))
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    $brRangeText.Text = ('Range {0:N1}-{1:N1} | {2}' -f $script:activeSettings.MinimumBR, $script:activeSettings.MaximumBR, $(if ($script:activeSettings.BRRollMode -eq 'Bracket') { 'BR brackets' } else { 'Specific BR' }))
    & $updateRollSessionAvailability
    $nationName.Text = 'Ready?'
    $brResult.Text = if ([string]::IsNullOrWhiteSpace([string]$script:activeSettings.CurrentBRResult)) { [string][char]0x2014 } else { [string]$script:activeSettings.CurrentBRResult }
    $restoredChallenge = @($script:challenges | Where-Object { $_.Id -eq [string]$script:activeSettings.CurrentChallengeId -and (Test-ContentDomain $_ $script:activeSettings.Domain) } | Select-Object -First 1)
    if ($restoredChallenge.Count -gt 0) {
        $script:currentChallenge = $restoredChallenge[0]
        $challengeName.Text = $script:currentChallenge.Name
        $challengeObjective.Text = $script:currentChallenge.Objective
        $challengeReward.Text = "SUCCESS: $($script:currentChallenge.Reward)"
        $startSessionButton.IsEnabled = $true
    }
    else {
        $script:activeSettings.CurrentChallengeId = ''
        $challengeName.Text = 'No challenge drawn'
        $challengeObjective.Text = 'Draw a challenge when your squad is feeling brave.'
        $challengeReward.Text = ''
        $script:currentChallenge = $null
        $startSessionButton.IsEnabled = $false
    }
    $funModeName.Text = 'No fun mode drawn'
    $funModeRule.Text = 'Draw a lineup constraint for additional questionable decisions.'
    $nationImage.Source = New-BitmapImage $emptyImagePath
    & $updateRemainingText
    & $updateChallengeRemainingText
    & $updateFunModeRemainingText
}

$script:activeProfileId = $null
$script:activePaths = $null
$script:activeSettings = $null
$profileSelector.DisplayMemberPath = 'Name'
$profileSelector.SelectedValuePath = 'Id'
$domainSelector.ItemsSource = $domains

$refreshProfileSelector = {
    param([string] $selectedProfileId)
    $profileSelector.ItemsSource = $null
    $profileSelector.ItemsSource = @($script:profileStore.Profiles)
    $profileSelector.SelectedValue = $selectedProfileId
}

& $refreshProfileSelector $script:profileStore.LastProfileId

$initialProfile = @($script:profileStore.Profiles | Where-Object Id -eq $script:profileStore.LastProfileId)[0]
if (-not $initialProfile) {
    $initialProfile = $script:profileStore.Profiles[0]
}
$profileSelector.SelectedValue = $initialProfile.Id
& $setActiveProfile $initialProfile.Id

$profileSelector.Add_SelectionChanged({
    if ($profileSelector.SelectedValue -and $profileSelector.SelectedValue -ne $script:activeProfileId) {
        & $setActiveProfile ([string]$profileSelector.SelectedValue)
    }
})

$domainSelector.Add_SelectionChanged({
    if (-not $script:domainChanging -and $script:activeSettings -and $domainSelector.SelectedValue) {
        & $applyDomain ([string]$domainSelector.SelectedValue) $true
    }
})

$manageButton.Add_Click({
    [xml]$manageXaml = Get-Content -LiteralPath $manageXamlFile -Raw
    $manageReader = [System.Xml.XmlNodeReader]::new($manageXaml)
    $manageWindow = [Windows.Markup.XamlReader]::Load($manageReader)
    $manageWindow.Owner = $window

    $manageProfileList = $manageWindow.FindName('ManageProfileList')
    $manageNewButton = $manageWindow.FindName('ManageNewProfileButton')
    $manageRenameButton = $manageWindow.FindName('ManageRenameProfileButton')
    $manageDeleteButton = $manageWindow.FindName('ManageDeleteProfileButton')
    $manageMinimumBR = $manageWindow.FindName('ManageMinimumBR')
    $manageMaximumBR = $manageWindow.FindName('ManageMaximumBR')
    $manageBRRollMode = $manageWindow.FindName('ManageBRRollMode')
    $manageCampaignTrack = $manageWindow.FindName('ManageCampaignTrack')
    $manageCampaignStage = $manageWindow.FindName('ManageCampaignStage')
    $manageResetBRButton = $manageWindow.FindName('ManageResetBRButton')
    $manageClearOnExit = $manageWindow.FindName('ManageClearOnExit')
    $manageEligibilityDomain = $manageWindow.FindName('ManageEligibilityDomain')
    $manageDomainNationPanel = $manageWindow.FindName('ManageDomainNationPanel')
    $restoreDomainEligibilityButton = $manageWindow.FindName('RestoreDomainEligibilityButton')
    $sessionRollNation = $manageWindow.FindName('SessionRollNation')
    $sessionRollBR = $manageWindow.FindName('SessionRollBR')
    $sessionRollChallenge = $manageWindow.FindName('SessionRollChallenge')
    $sessionRollFunMode = $manageWindow.FindName('SessionRollFunMode')
    $sessionModulesHint = $manageWindow.FindName('SessionModulesHint')
    $manageProgressionTrack = $manageWindow.FindName('ManageProgressionTrack')
    $manageProgressionStageList = $manageWindow.FindName('ManageProgressionStageList')
    $progressionSourceText = $manageWindow.FindName('ProgressionSourceText')
    $addExactStageButton = $manageWindow.FindName('AddExactStageButton')
    $addRangeStageButton = $manageWindow.FindName('AddRangeStageButton')
    $editStageButton = $manageWindow.FindName('EditStageButton')
    $toggleStageButton = $manageWindow.FindName('ToggleStageButton')
    $moveStageUpButton = $manageWindow.FindName('MoveStageUpButton')
    $moveStageDownButton = $manageWindow.FindName('MoveStageDownButton')
    $deleteStageButton = $manageWindow.FindName('DeleteStageButton')
    $restoreProgressionButton = $manageWindow.FindName('RestoreProgressionButton')
    $manageHistoryList = $manageWindow.FindName('ManageHistoryList')
    $manageHistorySummary = $manageWindow.FindName('ManageHistorySummary')
    $clearHistoryButton = $manageWindow.FindName('ClearHistoryButton')
    $manageChallengeList = $manageWindow.FindName('ManageChallengeList')
    $manageFunModeList = $manageWindow.FindName('ManageFunModeList')
    $addChallengeButton = $manageWindow.FindName('AddChallengeButton')
    $useSelectedChallengeButton = $manageWindow.FindName('UseSelectedChallengeButton')
    $editChallengeButton = $manageWindow.FindName('EditChallengeButton')
    $deleteChallengeButton = $manageWindow.FindName('DeleteChallengeButton')
    $restoreChallengesButton = $manageWindow.FindName('RestoreChallengesButton')
    $addFunModeButton = $manageWindow.FindName('AddFunModeButton')
    $useSelectedFunModeButton = $manageWindow.FindName('UseSelectedFunModeButton')
    $editFunModeButton = $manageWindow.FindName('EditFunModeButton')
    $deleteFunModeButton = $manageWindow.FindName('DeleteFunModeButton')
    $restoreFunModesButton = $manageWindow.FindName('RestoreFunModesButton')
    $resetChallengeDeckButton = $manageWindow.FindName('ResetChallengeDeckButton')
    $resetFunModeDeckButton = $manageWindow.FindName('ResetFunModeDeckButton')
    $manageCloseButton = $manageWindow.FindName('ManageCloseButton')

    $manageMinimumBR.ItemsSource = $brStages
    $manageMaximumBR.ItemsSource = $brStages
    $manageBRRollMode.ItemsSource = @(
        [pscustomobject]@{ Id='Exact'; Name='Specific BR (for example 4.3)' }
        [pscustomobject]@{ Id='Bracket'; Name='Whole BR bracket (for example 4.0-4.7)' }
    )
    $manageCampaignTrack.ItemsSource = @(Get-EligibleProgressionTracks $script:activeSettings.Domain)
    $manageProgressionTrack.ItemsSource = @($script:progressionCatalog.Tracks)
    $progressionSourceText.Text = "War Thunder $($script:progressionCatalog.Source.GameVersion)"
    $script:manageChanging = $false
    $manageEligibilityDomain.ItemsSource = @($domains | Where-Object Id -ne 'Any')

    $refreshDomainEligibility = {
        $manageDomainNationPanel.Children.Clear()
        $domain = Normalize-Domain ([string]$manageEligibilityDomain.SelectedValue)
        if ($domain -eq 'Any') { return }
        foreach ($nation in @($nations.Keys)) {
            $checkBox = [System.Windows.Controls.CheckBox]::new()
            $checkBox.Content = $nation
            $checkBox.Tag = $nation
            $checkBox.FontSize = 14
            $checkBox.Margin = [System.Windows.Thickness]::new(0,0,0,10)
            $checkBox.IsChecked = $nation -in @($script:domainNationEligibility[$domain])
            $checkBox.Add_Click({
                $clicked = $this
                $selectedDomain = Normalize-Domain ([string]$manageEligibilityDomain.SelectedValue)
                $enabled = @($manageDomainNationPanel.Children | Where-Object IsChecked | ForEach-Object { [string]$_.Tag })
                if ($enabled.Count -eq 0) {
                    $clicked.IsChecked = $true
                    [System.Windows.MessageBox]::Show('At least one nation must remain enabled for a domain.', 'Thunder Roulette') | Out-Null
                    return
                }
                $script:domainNationEligibility[$selectedDomain] = $enabled
                Save-DomainSettings
                if ([string]$script:activeSettings.Domain -eq $selectedDomain) {
                    Reset-NationQueue
                    $nationName.Text = 'Ready?'
                    $nationImage.Source = New-BitmapImage $emptyImagePath
                    & $updateRemainingText
                }
            })
            $manageDomainNationPanel.Children.Add($checkBox) | Out-Null
        }
    }

    $getSelectedProgressionTrack = {
        if (-not $manageProgressionTrack.SelectedValue) { return $null }
        return @($script:progressionCatalog.Tracks | Where-Object { $_.Id -eq [string]$manageProgressionTrack.SelectedValue })[0]
    }

    $refreshProgressionStages = {
        param([string] $selectedStageId)
        $track = & $getSelectedProgressionTrack
        $manageProgressionStageList.ItemsSource = $null
        if (-not $track) { return }
        foreach ($stage in @($track.Stages)) {
            $stage | Add-Member -NotePropertyName DisplayLabel -NotePropertyValue "$(if (-not $stage.Enabled) { '[Disabled] ' })$($stage.Label)" -Force
        }
        $manageProgressionStageList.DisplayMemberPath = 'DisplayLabel'
        $manageProgressionStageList.ItemsSource = @($track.Stages)
        if ($selectedStageId) { $manageProgressionStageList.SelectedItem = @($track.Stages | Where-Object Id -eq $selectedStageId)[0] }
    }

    $readDiameter = {
        param([string] $prompt, [string] $title, [string] $defaultValue)
        $text = [Microsoft.VisualBasic.Interaction]::InputBox($prompt, $title, $defaultValue).Trim().Replace(',', '.')
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $value = 0.0
        if (-not [double]::TryParse($text, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -le 0) {
            [System.Windows.MessageBox]::Show('Enter a positive diameter in millimetres.', 'Thunder Roulette') | Out-Null
            return $null
        }
        return [double]$value
    }

    $refreshContentLists = {
        param([string] $challengeId, [string] $funModeId)
        foreach ($item in @($script:challenges) + @($script:funModes)) { $item | Add-Member -NotePropertyName DisplayLabel -NotePropertyValue "[$($item.Domain)] $($item.Name)" -Force }
        $manageChallengeList.DisplayMemberPath = 'DisplayLabel'
        $manageFunModeList.DisplayMemberPath = 'DisplayLabel'
        $manageChallengeList.ItemsSource = $null
        $manageChallengeList.ItemsSource = @($script:challenges)
        $manageFunModeList.ItemsSource = $null
        $manageFunModeList.ItemsSource = @($script:funModes)
        if ($challengeId) { $manageChallengeList.SelectedItem = @($script:challenges | Where-Object Id -eq $challengeId)[0] }
        if ($funModeId) { $manageFunModeList.SelectedItem = @($script:funModes | Where-Object Id -eq $funModeId)[0] }
    }

    $refreshManageProfiles = {
        param([string] $selectedId)
        $manageProfileList.ItemsSource = $null
        $manageProfileList.ItemsSource = @($script:profileStore.Profiles)
        $manageProfileList.SelectedValue = $selectedId
        $manageDeleteButton.IsEnabled = @($script:profileStore.Profiles).Count -gt 1
    }

    $refreshCampaignStages = {
        param([int] $selectedIndex)
        $track = @($script:progressionCatalog.Tracks | Where-Object { $_.Id -eq [string]$manageCampaignTrack.SelectedValue } | Select-Object -First 1)
        $manageCampaignStage.ItemsSource = $null
        if ($track.Count -eq 0) { return }
        $enabledStages = @($track[0].Stages | Where-Object Enabled)
        $manageCampaignStage.ItemsSource = $enabledStages
        if ($enabledStages.Count -gt 0) { $manageCampaignStage.SelectedIndex = [math]::Min([math]::Max(0, $selectedIndex), $enabledStages.Count - 1) }
    }

    $refreshSessionHistory = {
        $history = @(Get-SessionHistory)
        Save-SessionHistory $history
        $history = @($history | Where-Object { $null -ne $_ })
        $readHistoryValue = {
            param($record, [string] $name, $fallback)
            if ($record -and $record.PSObject.Properties[$name]) { return $record.PSObject.Properties[$name].Value }
            return $fallback
        }
        $displayHistory = @($history | Sort-Object { & $readHistoryValue $_ 'EndedAt' (& $readHistoryValue $_ 'StartedAt' '') } -Descending | ForEach-Object {
            $endedAt = & $readHistoryValue $_ 'EndedAt' (& $readHistoryValue $_ 'StartedAt' '')
            $when = if ([string]::IsNullOrWhiteSpace([string]$endedAt)) { 'Unknown date' } else {
                try { ([datetime]$endedAt).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } catch { [string]$endedAt }
            }
            $durationSeconds = [int](& $readHistoryValue $_ 'DurationSeconds' 0)
            $duration = [timespan]::FromSeconds([math]::Max(0, $durationSeconds))
            $outcome = [string](& $readHistoryValue $_ 'Outcome' 'Legacy')
            $challenge = [string](& $readHistoryValue $_ 'ChallengeName' (& $readHistoryValue $_ 'Challenge' 'Unknown challenge'))
            $nation = [string](& $readHistoryValue $_ 'Nation' 'Unknown')
            $startingBR = & $readHistoryValue $_ 'StartingBR' $null
            $endingBR = & $readHistoryValue $_ 'EndingBR' $null
            $startingStage = [string](& $readHistoryValue $_ 'StartingStage' '')
            $endingStage = [string](& $readHistoryValue $_ 'EndingStage' '')
            $successes = [int](& $readHistoryValue $_ 'SuccessCount' 0)
            $failures = [int](& $readHistoryValue $_ 'FailureCount' 0)
            $sessionNotes = [string](& $readHistoryValue $_ 'Notes' '')
            $attempts = @(& $readHistoryValue $_ 'Attempts' @())
            $progressSummary = if ($startingStage -or $endingStage) { " | $startingStage -> $endingStage" } else { '' }
            $detailParts = @("Nation: $nation")
            if ($null -ne $startingBR -or $null -ne $endingBR) { $detailParts += "BR: $startingBR -> $endingBR" }
            if ($startingStage -or $endingStage) { $detailParts += "Stage: $startingStage -> $endingStage" }
            $attemptParts = @()
            if ($successes -gt 0) { $attemptParts += "$successes success$(if ($successes -ne 1) { 'es' })" }
            if ($failures -gt 0) { $attemptParts += "$failures failure$(if ($failures -ne 1) { 's' })" }
            $attemptSummary = if ($attemptParts.Count -gt 0) { ' (' + ($attemptParts -join ', ') + ')' } else { '' }
            $attemptLines = @(
                foreach ($attempt in $attempts) {
                    if (-not $attempt) { continue }
                    $number = & $readHistoryValue $attempt 'Number' '?'
                    $attemptOutcome = [string](& $readHistoryValue $attempt 'Outcome' 'Attempt')
                    $parts = @("#$number $attemptOutcome")
                    foreach ($trackerValue in @(& $readHistoryValue $attempt 'TrackerValues' @())) {
                        $label = [string](& $readHistoryValue $trackerValue 'Label' 'Tracker')
                        $type = [string](& $readHistoryValue $trackerValue 'Type' 'Counter')
                        $value = & $readHistoryValue $trackerValue 'Value' 0
                        $target = & $readHistoryValue $trackerValue 'Target' 1
                        $parts += if ($type -eq 'Checkbox') { "$label`: $(if ([bool]$value) { 'Yes' } else { 'No' })" } else { "$label`: $value / $target" }
                    }
                    $attemptStartBR = & $readHistoryValue $attempt 'StartingBR' $null
                    $attemptEndBR = & $readHistoryValue $attempt 'EndingBR' $null
                    if ($null -ne $attemptStartBR -or $null -ne $attemptEndBR) { $parts += "BR $attemptStartBR -> $attemptEndBR" }
                    $attemptStartStage = & $readHistoryValue $attempt 'StartingStage' $null
                    $attemptEndStage = & $readHistoryValue $attempt 'EndingStage' $null
                    if ($attemptStartStage -or $attemptEndStage) { $parts += "Stage $attemptStartStage -> $attemptEndStage" }
                    $attemptNote = [string](& $readHistoryValue $attempt 'Notes' '')
                    if (-not [string]::IsNullOrWhiteSpace($attemptNote)) { $parts += "Notes: $attemptNote" }
                    $parts -join ' | '
                }
            )
            [pscustomobject]@{
                Summary = ('{0} | {1}{2} | {3}{4} | {5:mm\:ss}' -f $when, $outcome, $attemptSummary, $challenge, $progressSummary, $duration)
                Detail = $detailParts -join '   '
                Attempts = [string]::Join([Environment]::NewLine, $attemptLines)
                Notes = if ($attempts.Count -gt 0 -or [string]::IsNullOrWhiteSpace($sessionNotes)) { '' } else { "Notes: $sessionNotes" }
            }
        })
        $manageHistoryList.ItemsSource = $null
        $manageHistoryList.ItemsSource = $displayHistory
        $manageHistorySummary.Text = if ($displayHistory.Count -eq 0) { 'No sessions recorded for this profile yet.' } else { "$($displayHistory.Count) recorded session$(if ($displayHistory.Count -ne 1) { 's' })" }
        $clearHistoryButton.IsEnabled = $displayHistory.Count -gt 0
    }

    $loadManageSettings = {
        $script:manageChanging = $true
        $manageCampaignTrack.ItemsSource = @(Get-EligibleProgressionTracks $script:activeSettings.Domain)
        $manageMinimumBR.SelectedItem = [double]$script:activeSettings.MinimumBR
        $manageMaximumBR.SelectedItem = [double]$script:activeSettings.MaximumBR
        $manageBRRollMode.SelectedValue = [string]$script:activeSettings.BRRollMode
        if (-not $manageBRRollMode.SelectedValue) { $manageBRRollMode.SelectedValue = 'Exact' }
        $manageCampaignTrack.SelectedValue = [string]$script:activeSettings.CampaignTrackId
        if (-not $manageCampaignTrack.SelectedValue) { $manageCampaignTrack.SelectedValue = 'ground-gun' }
        & $refreshCampaignStages ([int]$script:activeSettings.CampaignStageIndex)
        $manageClearOnExit.IsChecked = [bool]$script:activeSettings.ClearSequenceOnExit
        $sessionRollNation.IsChecked = [bool]$script:activeSettings.SessionRollNation
        $sessionRollBR.IsChecked = [bool]$script:activeSettings.SessionRollBR
        $sessionRollChallenge.IsChecked = [bool]$script:activeSettings.SessionRollChallenge
        $sessionRollFunMode.IsChecked = [bool]$script:activeSettings.SessionRollFunMode
        $sessionModulesHint.Visibility = if ($rollSessionButton.IsEnabled) {
            [System.Windows.Visibility]::Collapsed
        }
        else {
            [System.Windows.Visibility]::Visible
        }
        $script:manageChanging = $false
    }

    $saveManageSettings = {
        if ($script:manageChanging) { return }
        if ([double]$manageMinimumBR.SelectedItem -gt [double]$manageMaximumBR.SelectedItem) {
            $script:manageChanging = $true
            $manageMaximumBR.SelectedItem = $manageMinimumBR.SelectedItem
            $script:manageChanging = $false
        }
        $oldMinimumBR = [double]$script:activeSettings.MinimumBR
        $oldMaximumBR = [double]$script:activeSettings.MaximumBR
        $oldBRRollMode = [string]$script:activeSettings.BRRollMode
        $script:activeSettings.MinimumBR = [double]$manageMinimumBR.SelectedItem
        $script:activeSettings.MaximumBR = [double]$manageMaximumBR.SelectedItem
        $script:activeSettings.BRRollMode = if ([string]$manageBRRollMode.SelectedValue -eq 'Bracket') { 'Bracket' } else { 'Exact' }
        if ($oldMinimumBR -ne [double]$script:activeSettings.MinimumBR -or $oldMaximumBR -ne [double]$script:activeSettings.MaximumBR -or $oldBRRollMode -ne [string]$script:activeSettings.BRRollMode) {
            Reset-BRQueue
            $script:activeSettings.CurrentBRResult = ''
            $brResult.Text = [string][char]0x2014
        }
        $script:activeSettings.ClearSequenceOnExit = [bool]$manageClearOnExit.IsChecked
        if ($manageCampaignTrack.SelectedValue) { $script:activeSettings.CampaignTrackId = [string]$manageCampaignTrack.SelectedValue }
        if ($manageCampaignStage.SelectedIndex -ge 0) { $script:activeSettings.CampaignStageIndex = [int]$manageCampaignStage.SelectedIndex }
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
        $brRangeText.Text = ('Range {0:N1}-{1:N1} | {2}' -f $script:activeSettings.MinimumBR, $script:activeSettings.MaximumBR, $(if ($script:activeSettings.BRRollMode -eq 'Bracket') { 'BR brackets' } else { 'Specific BR' }))
    }

    & $refreshManageProfiles $script:activeProfileId
    & $loadManageSettings
    & $refreshSessionHistory
    & $refreshContentLists $null $null
    $manageEligibilityDomain.SelectedValue = if ([string]$script:activeSettings.Domain -eq 'Any') { 'Ground' } else { [string]$script:activeSettings.Domain }
    & $refreshDomainEligibility
    $manageProgressionTrack.SelectedIndex = 0
    & $refreshProgressionStages $null

    $manageProfileList.Add_SelectionChanged({
        if ($manageProfileList.SelectedValue -and $manageProfileList.SelectedValue -ne $script:activeProfileId) {
            & $setActiveProfile ([string]$manageProfileList.SelectedValue)
            & $refreshProfileSelector $script:activeProfileId
            & $loadManageSettings
            & $refreshSessionHistory
        }
    })

    $manageEligibilityDomain.Add_SelectionChanged({ & $refreshDomainEligibility })
    $restoreDomainEligibilityButton.Add_Click({
        foreach ($domain in @('Ground','Air','Naval')) { $script:domainNationEligibility[$domain] = @($defaultDomainNationEligibility[$domain]) }
        Save-DomainSettings
        & $refreshDomainEligibility
        Reset-NationQueue
        & $updateRemainingText
    })

    $clearHistoryButton.Add_Click({
        if ([System.Windows.MessageBox]::Show('Clear the session history for this profile?', 'Thunder Roulette', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        '[]' | Set-Content -LiteralPath $script:activePaths.SessionHistory -Encoding UTF8
        & $refreshSessionHistory
    })

    $manageNewButton.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Who is this profile for?', 'Create new profile', '').Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        if (@($script:profileStore.Profiles | Where-Object Name -ieq $name).Count -gt 0) {
            [System.Windows.MessageBox]::Show('That profile name already exists.', 'Thunder Roulette') | Out-Null
            return
        }
        $profile = [pscustomobject]@{ Id = [guid]::NewGuid().ToString('N'); Name = $name }
        $script:profileStore.Profiles = @($script:profileStore.Profiles) + $profile
        Save-ProfileStore
        & $refreshProfileSelector $script:activeProfileId
        & $refreshManageProfiles $profile.Id
    })

    $manageRenameButton.Add_Click({
        $profile = @($script:profileStore.Profiles | Where-Object Id -eq $script:activeProfileId)[0]
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Choose a new profile name.', 'Rename profile', $profile.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($name) -or $name -ceq $profile.Name) { return }
        if (@($script:profileStore.Profiles | Where-Object { $_.Id -ne $profile.Id -and $_.Name -ieq $name }).Count -gt 0) {
            [System.Windows.MessageBox]::Show('That profile name already exists.', 'Thunder Roulette') | Out-Null
            return
        }
        $profile.Name = $name
        Save-ProfileStore
        & $refreshManageProfiles $profile.Id
        & $refreshProfileSelector $profile.Id
    })

    $manageDeleteButton.Add_Click({
        if (@($script:profileStore.Profiles).Count -le 1) { return }
        $profile = @($script:profileStore.Profiles | Where-Object Id -eq $script:activeProfileId)[0]
        $answer = [System.Windows.MessageBox]::Show("Delete profile '$($profile.Name)'? Its data will be archived.", 'Delete profile', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $directory = Split-Path -Parent $script:activePaths.Queue
        $archiveName = '{0}-{1}' -f $profile.Id, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Move-Item -LiteralPath $directory -Destination (Join-Path $deletedProfilesDirectory $archiveName)
        $script:profileStore.Profiles = @($script:profileStore.Profiles | Where-Object Id -ne $profile.Id)
        $next = $script:profileStore.Profiles[0]
        $script:activeProfileId = $null; $script:activePaths = $null; $script:activeSettings = $null
        & $setActiveProfile $next.Id
        & $refreshProfileSelector $next.Id
        & $refreshManageProfiles $next.Id
        & $loadManageSettings
    })

    $manageMinimumBR.Add_SelectionChanged({ & $saveManageSettings })
    $manageBRRollMode.Add_SelectionChanged({ & $saveManageSettings })
    $manageMaximumBR.Add_SelectionChanged({
        if (-not $script:manageChanging -and [double]$manageMaximumBR.SelectedItem -lt [double]$manageMinimumBR.SelectedItem) {
            $script:manageChanging = $true
            $manageMinimumBR.SelectedItem = $manageMaximumBR.SelectedItem
            $script:manageChanging = $false
        }
        & $saveManageSettings
    })
    $manageCampaignTrack.Add_SelectionChanged({
        if ($script:manageChanging) { return }
        & $refreshCampaignStages 0
        & $saveManageSettings
    })
    $manageCampaignStage.Add_SelectionChanged({ & $saveManageSettings })
    $manageClearOnExit.Add_Click({ & $saveManageSettings })
    $manageResetBRButton.Add_Click({
        Reset-BRQueue
        $script:activeSettings.CurrentBRResult = ''
        $brResult.Text = [string][char]0x2014
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    })

    $saveSessionModules = {
        if ($script:manageChanging) { return }
        $script:activeSettings.SessionRollNation = [bool]$sessionRollNation.IsChecked
        $script:activeSettings.SessionRollBR = [bool]$sessionRollBR.IsChecked
        $script:activeSettings.SessionRollChallenge = [bool]$sessionRollChallenge.IsChecked
        $script:activeSettings.SessionRollFunMode = [bool]$sessionRollFunMode.IsChecked
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
        & $updateRollSessionAvailability
        $sessionModulesHint.Visibility = if ($rollSessionButton.IsEnabled) {
            [System.Windows.Visibility]::Collapsed
        }
        else {
            [System.Windows.Visibility]::Visible
        }
    }
    $sessionRollNation.Add_Click({ & $saveSessionModules })
    $sessionRollBR.Add_Click({ & $saveSessionModules })
    $sessionRollChallenge.Add_Click({ & $saveSessionModules })
    $sessionRollFunMode.Add_Click({ & $saveSessionModules })

    $manageProgressionTrack.Add_SelectionChanged({ & $refreshProgressionStages $null })

    $addExactStageButton.Add_Click({
        $track = & $getSelectedProgressionTrack
        if (-not $track) { return }
        $value = & $readDiameter 'Exact diameter in millimetres:' 'Add progression stage' ''
        if ($null -eq $value) { return }
        $stage = [pscustomobject]@{
            Id = [guid]::NewGuid().ToString('N'); Type = 'Exact'
            Minimum = $value; Maximum = $value; Label = Format-DiameterLabel $value $value
            Enabled = $true; SortOrder = @($track.Stages).Count
        }
        $track.Stages = @($track.Stages) + $stage
        Save-ProgressionCatalog
        & $refreshProgressionStages $stage.Id
    })

    $addRangeStageButton.Add_Click({
        $track = & $getSelectedProgressionTrack
        if (-not $track) { return }
        $minimum = & $readDiameter 'Minimum diameter in millimetres:' 'Add progression range' ''
        if ($null -eq $minimum) { return }
        $maximum = & $readDiameter 'Maximum diameter in millimetres:' 'Add progression range' ([string]$minimum)
        if ($null -eq $maximum) { return }
        if ($maximum -lt $minimum) { $temporary = $minimum; $minimum = $maximum; $maximum = $temporary }
        $stage = [pscustomobject]@{
            Id = [guid]::NewGuid().ToString('N'); Type = if ($minimum -eq $maximum) { 'Exact' } else { 'Range' }
            Minimum = $minimum; Maximum = $maximum; Label = Format-DiameterLabel $minimum $maximum
            Enabled = $true; SortOrder = @($track.Stages).Count
        }
        $track.Stages = @($track.Stages) + $stage
        Save-ProgressionCatalog
        & $refreshProgressionStages $stage.Id
    })

    $editStageButton.Add_Click({
        $stage = $manageProgressionStageList.SelectedItem
        if (-not $stage) { return }
        $minimum = & $readDiameter 'Minimum diameter in millimetres:' 'Edit progression stage' ([string]$stage.Minimum)
        if ($null -eq $minimum) { return }
        $maximum = & $readDiameter 'Maximum diameter in millimetres:' 'Edit progression stage' ([string]$stage.Maximum)
        if ($null -eq $maximum) { return }
        if ($maximum -lt $minimum) { $temporary = $minimum; $minimum = $maximum; $maximum = $temporary }
        $defaultLabel = Format-DiameterLabel $minimum $maximum
        $label = [Microsoft.VisualBasic.Interaction]::InputBox('Display label:', 'Edit progression stage', $defaultLabel).Trim()
        if ([string]::IsNullOrWhiteSpace($label)) { return }
        $stage.Minimum = $minimum; $stage.Maximum = $maximum
        $stage.Type = if ($minimum -eq $maximum) { 'Exact' } else { 'Range' }
        $stage.Label = $label
        Save-ProgressionCatalog
        & $refreshProgressionStages $stage.Id
    })

    $toggleStageButton.Add_Click({
        $stage = $manageProgressionStageList.SelectedItem
        if (-not $stage) { return }
        $stage.Enabled = -not [bool]$stage.Enabled
        Save-ProgressionCatalog
        & $refreshProgressionStages $stage.Id
    })

    $moveProgressionStage = {
        param([int] $direction)
        $track = & $getSelectedProgressionTrack
        $stage = $manageProgressionStageList.SelectedItem
        if (-not $track -or -not $stage) { return }
        $stages = @($track.Stages)
        $index = [array]::IndexOf($stages, $stage)
        $target = $index + $direction
        if ($index -lt 0 -or $target -lt 0 -or $target -ge $stages.Count) { return }
        $temporary = $stages[$target]; $stages[$target] = $stage; $stages[$index] = $temporary
        for ($position = 0; $position -lt $stages.Count; $position++) { $stages[$position].SortOrder = $position }
        $track.Stages = $stages
        Save-ProgressionCatalog
        & $refreshProgressionStages $stage.Id
    }
    $moveStageUpButton.Add_Click({ & $moveProgressionStage -1 })
    $moveStageDownButton.Add_Click({ & $moveProgressionStage 1 })

    $deleteStageButton.Add_Click({
        $track = & $getSelectedProgressionTrack
        $stage = $manageProgressionStageList.SelectedItem
        if (-not $track -or -not $stage -or @($track.Stages).Count -le 1) { return }
        if ([System.Windows.MessageBox]::Show("Delete progression stage '$($stage.Label)'?", 'Thunder Roulette', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $track.Stages = @($track.Stages | Where-Object Id -ne $stage.Id)
        for ($position = 0; $position -lt @($track.Stages).Count; $position++) { $track.Stages[$position].SortOrder = $position }
        Save-ProgressionCatalog
        & $refreshProgressionStages $null
    })

    $restoreProgressionButton.Add_Click({
        if ([System.Windows.MessageBox]::Show('Replace all progression tracks with the shipped 2.57.1.68 catalog?', 'Restore progression catalog', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $selectedTrackId = [string]$manageProgressionTrack.SelectedValue
        Restore-ProgressionCatalog
        $manageProgressionTrack.ItemsSource = $null
        $manageProgressionTrack.ItemsSource = @($script:progressionCatalog.Tracks)
        $manageProgressionTrack.SelectedValue = $selectedTrackId
        if (-not $manageProgressionTrack.SelectedValue) { $manageProgressionTrack.SelectedIndex = 0 }
        $progressionSourceText.Text = "War Thunder $($script:progressionCatalog.Source.GameVersion)"
        & $refreshProgressionStages $null
    })

    $useSelectedChallengeButton.Add_Click({
        $card = $manageChallengeList.SelectedItem
        if (-not $card) { return }
        if (-not (Test-ContentDomain $card $script:activeSettings.Domain)) {
            [System.Windows.MessageBox]::Show("'$($card.Name)' is a $($card.Domain) challenge. Switch the main domain selector first.", 'Thunder Roulette') | Out-Null
            return
        }
        $script:currentChallenge = $card
        $script:activeSettings.CurrentChallengeId = [string]$card.Id
        $challengeName.Text = [string]$card.Name
        $challengeObjective.Text = [string]$card.Objective
        $challengeReward.Text = "SUCCESS: $($card.Reward)"
        $startSessionButton.IsEnabled = $true
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    })

    $useSelectedFunModeButton.Add_Click({
        $card = $manageFunModeList.SelectedItem
        if (-not $card) { return }
        if (-not (Test-ContentDomain $card $script:activeSettings.Domain)) {
            [System.Windows.MessageBox]::Show("'$($card.Name)' is a $($card.Domain) fun mode. Switch the main domain selector first.", 'Thunder Roulette') | Out-Null
            return
        }
        $funModeName.Text = [string]$card.Name
        $funModeRule.Text = [string]$card.Rule
    })

    $addChallengeButton.Add_Click({
        $card = Show-ChallengeEditor $manageWindow $null
        if (-not $card) { return }
        $script:challenges = @($script:challenges) + $card
        Save-ContentLibraries
        & $refreshContentLists $card.Id $null
    })

    $editChallengeButton.Add_Click({
        $card = $manageChallengeList.SelectedItem
        if (-not $card) { return }
        $edited = Show-ChallengeEditor $manageWindow $card
        if (-not $edited) { return }
        $index = [array]::IndexOf(@($script:challenges), $card)
        $script:challenges[$index] = $edited
        Save-ContentLibraries
        & $refreshCurrentChallengeFromLibrary
        & $refreshContentLists $edited.Id $null
    })

    $deleteChallengeButton.Add_Click({
        $card = $manageChallengeList.SelectedItem
        if (-not $card -or @($script:challenges).Count -le 1) { return }
        if ([System.Windows.MessageBox]::Show("Delete challenge '$($card.Name)'?", 'Delete challenge', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:challenges = @($script:challenges | Where-Object Id -ne $card.Id)
        Save-ContentLibraries
        & $refreshCurrentChallengeFromLibrary
        & $refreshContentLists $null $null
    })

    $addFunModeButton.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Fun-mode name:', 'Add fun mode', '').Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $rule = [Microsoft.VisualBasic.Interaction]::InputBox('What lineup or playstyle rule applies?', 'Fun-mode rule', '').Trim()
        if ([string]::IsNullOrWhiteSpace($rule)) { return }
        $domain = Normalize-Domain ([Microsoft.VisualBasic.Interaction]::InputBox('Vehicle domain: Any, Ground, Air, or Naval', 'Fun-mode domain', 'Any').Trim())
        $card = [pscustomobject]@{ Id = 'custom-' + [guid]::NewGuid().ToString('N'); Name = $name; Rule = $rule; Domain = $domain }
        $script:funModes = @($script:funModes) + $card
        Save-ContentLibraries
        & $refreshContentLists $null $card.Id
    })

    $editFunModeButton.Add_Click({
        $card = $manageFunModeList.SelectedItem
        if (-not $card) { return }
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Fun-mode name:', 'Edit fun mode', $card.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $rule = [Microsoft.VisualBasic.Interaction]::InputBox('What lineup or playstyle rule applies?', 'Fun-mode rule', $card.Rule).Trim()
        if ([string]::IsNullOrWhiteSpace($rule)) { return }
        $domain = Normalize-Domain ([Microsoft.VisualBasic.Interaction]::InputBox('Vehicle domain: Any, Ground, Air, or Naval', 'Fun-mode domain', $card.Domain).Trim())
        $card.Name = $name; $card.Rule = $rule; $card.Domain = $domain
        Save-ContentLibraries
        & $refreshContentLists $null $card.Id
    })

    $deleteFunModeButton.Add_Click({
        $card = $manageFunModeList.SelectedItem
        if (-not $card -or @($script:funModes).Count -le 1) { return }
        if ([System.Windows.MessageBox]::Show("Delete fun mode '$($card.Name)'?", 'Delete fun mode', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:funModes = @($script:funModes | Where-Object Id -ne $card.Id)
        Save-ContentLibraries
        & $refreshContentLists $null $null
    })

    $restoreChallengesButton.Add_Click({
        if ([System.Windows.MessageBox]::Show('Replace all challenges with the shipped defaults?', 'Restore challenges', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:challenges = @($defaultChallenges | ForEach-Object { ConvertTo-Challenge $_ })
        Save-ContentLibraries
        & $refreshCurrentChallengeFromLibrary
        Clear-Content -LiteralPath (Get-DomainQueuePath 'Challenge')
        & $refreshContentLists $null $null
        & $updateChallengeRemainingText
    })

    $restoreFunModesButton.Add_Click({
        if ([System.Windows.MessageBox]::Show('Replace all fun modes with the shipped defaults?', 'Restore fun modes', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:funModes = @($defaultFunModes | ForEach-Object { ConvertTo-FunMode $_ })
        Save-ContentLibraries
        Clear-Content -LiteralPath (Get-DomainQueuePath 'FunMode')
        & $refreshContentLists $null $null
        & $updateFunModeRemainingText
    })

    $resetChallengeDeckButton.Add_Click({
        Clear-Content -LiteralPath (Get-DomainQueuePath 'Challenge')
        & $clearCurrentChallenge
        & $updateChallengeRemainingText
    })
    $resetFunModeDeckButton.Add_Click({
        Clear-Content -LiteralPath (Get-DomainQueuePath 'FunMode')
        & $clearCurrentFunMode
        & $updateFunModeRemainingText
    })
    $manageCloseButton.Add_Click({ $manageWindow.Close() })

    $null = $manageWindow.ShowDialog()
})

$rollNation = {
    $selectedNation = Get-NextNation
    $nationName.Text = $selectedNation
    $nationImage.Source = New-BitmapImage (Join-Path $appRoot "Assets\NationIcons\$($nations[$selectedNation])")
    & $updateRemainingText
}

$resetButton.Add_Click({
    Reset-NationQueue
    $nationName.Text = 'Ready?'
    $nationImage.Source = New-BitmapImage $emptyImagePath
    & $updateRemainingText
})

$rollBattleRating = {
    if ([string]$script:activeSettings.BRRollMode -eq 'Bracket') {
        $selectedBracket = Get-NextBRBracket
        $script:activeSettings.CampaignBR = [double]$selectedBracket.Minimum
        $brResult.Text = [string]$selectedBracket.Label
    }
    else {
        $selectedRating = Get-NextBR
        $script:activeSettings.CampaignBR = $selectedRating
        $brResult.Text = ('{0:N1}' -f $selectedRating)
    }
    $script:activeSettings.CurrentBRResult = [string]$brResult.Text
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
}

$rollChallenge = {
    $challenge = Get-NextChallenge
    $script:currentChallenge = $challenge
    $script:activeSettings.CurrentChallengeId = [string]$challenge.Id
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    $startSessionButton.IsEnabled = $true
    $challengeName.Text = $challenge.Name
    $challengeObjective.Text = $challenge.Objective
    $challengeReward.Text = "SUCCESS: $($challenge.Reward)"
    & $updateChallengeRemainingText
}

$rollFunMode = {
    $funMode = Get-NextFunMode
    $funModeName.Text = $funMode.Name
    $funModeRule.Text = $funMode.Rule
    & $updateFunModeRemainingText
}

$rollButton.Add_Click({ & $rollNation })
$rollBRButton.Add_Click({ & $rollBattleRating })
$rollChallengeButton.Add_Click({ & $rollChallenge })
$rollFunModeButton.Add_Click({ & $rollFunMode })
$rollSessionButton.Add_Click({
    if ($script:activeSettings.SessionRollNation) { & $rollNation }
    if ($script:activeSettings.SessionRollBR) { & $rollBattleRating }
    if ($script:activeSettings.SessionRollChallenge) { & $rollChallenge }
    if ($script:activeSettings.SessionRollFunMode) { & $rollFunMode }
})

$resetAllButton.Add_Click({
    if ([System.Windows.MessageBox]::Show('Reset the current profile roulette state? Profiles, custom content, history, and campaign progress will be kept.', 'Reset all', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question) -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Reset-NationQueue
    Reset-BRQueue
    Clear-Content -LiteralPath (Get-DomainQueuePath 'Challenge')
    Clear-Content -LiteralPath (Get-DomainQueuePath 'FunMode')
    $nationName.Text = 'Ready?'
    $nationImage.Source = New-BitmapImage $emptyImagePath
    $script:activeSettings.CurrentBRResult = ''
    $brResult.Text = [string][char]0x2014
    & $clearCurrentChallenge
    & $clearCurrentFunMode
    & $updateRemainingText
    & $updateChallengeRemainingText
    & $updateFunModeRemainingText
})

$startSessionButton.Add_Click({
    if (-not $script:currentChallenge) { return }
    $track = @($script:progressionCatalog.Tracks | Where-Object { $_.Id -eq $script:activeSettings.CampaignTrackId } | Select-Object -First 1)[0]
    $enabledStages = @($track.Stages | Where-Object Enabled)
    $stageIndex = if ($enabledStages.Count -eq 0) { -1 } else { [math]::Min([int]$script:activeSettings.CampaignStageIndex, $enabledStages.Count - 1) }
    $stage = if ($stageIndex -ge 0) { $enabledStages[$stageIndex] } else { $null }
    $nation = if ($nationName.Text -eq 'Ready?') { 'Not rolled' } else { $nationName.Text }
    $battleRatingWasRolled = $brResult.Text -ne [string][char]0x2014
    $challengeUsesBR = $script:currentChallenge.RewardAction.Type -eq 'BRSteps' -or $script:currentChallenge.FailureAction.Type -eq 'BRStepsDown'
    $challengeUsesTrack = $script:currentChallenge.RewardAction.Type -eq 'TrackSteps' -or $script:currentChallenge.FailureAction.Type -eq 'TrackStepsDown'
    $battleRating = if ($battleRatingWasRolled) { $brResult.Text } elseif (-not $challengeUsesBR) { '' } else { '{0:N1}' -f $script:activeSettings.CampaignBR }
    $funMode = if ($funModeName.Text -eq 'No fun mode drawn') { 'None' } else { $funModeName.Text }
    $startingBR = [double]$script:activeSettings.CampaignBR
    $startingStage = if ($stage) { $stage.Label } else { $null }
    $sessionChallenge = $script:currentChallenge
    $successCommand = Get-Command Invoke-CampaignSuccess -CommandType Function
    $failureCommand = Get-Command Invoke-CampaignFailure -CommandType Function
    $advanceCampaign = { & $successCommand $sessionChallenge $enabledStages $battleRatingWasRolled }.GetNewClosure()
    $punishCampaign = { & $failureCommand $sessionChallenge $enabledStages $battleRatingWasRolled }.GetNewClosure()

    $result = Show-SessionWindow $window $script:currentChallenge $nation $battleRating $funMode $track $stage $advanceCampaign $punishCampaign

    $endingStage = if ($enabledStages.Count -gt 0) { $enabledStages[[math]::Min([int]$script:activeSettings.CampaignStageIndex, $enabledStages.Count - 1)].Label } else { $null }
    Add-SessionHistoryRecord ([pscustomobject]@{
        Id=[guid]::NewGuid().ToString('N'); ChallengeId=$script:currentChallenge.Id; ChallengeName=$script:currentChallenge.Name
        Domain=[string]$script:activeSettings.Domain; Nation=$nation; StartingBR=$(if ($challengeUsesBR) { if (-not [string]::IsNullOrWhiteSpace($battleRating)) { $battleRating } else { Get-CampaignBRDisplay } } else { $null }); FunMode=$funMode; TrackId=$(if ($challengeUsesTrack) { $track.Id } else { $null })
        StartingStage=$(if ($challengeUsesTrack) { $startingStage } else { $null }); EndingStage=$(if ($challengeUsesTrack) { $endingStage } else { $null })
        EndingBR=$(if ($challengeUsesBR) { Get-CampaignBRDisplay } else { $null })
        Outcome=$result.Outcome; StartedAt=$result.StartedAt; EndedAt=$result.EndedAt
        DurationSeconds=$result.DurationSeconds; SuccessCount=$result.SuccessCount; FailureCount=$result.FailureCount
        Notes=$result.Notes; TrackerValues=$result.TrackerValues; Attempts=$result.Attempts
    })
})

$window.Add_Closed({
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    if ([bool]$script:activeSettings.ClearSequenceOnExit) {
        Reset-NationQueue
    }
})

if ($ValidateOnly) {
    $expectedBRResult = if ([string]::IsNullOrWhiteSpace([string]$script:activeSettings.CurrentBRResult)) { [string][char]0x2014 } else { [string]$script:activeSettings.CurrentBRResult }
    if ($brResult.Text -ne $expectedBRResult) {
        throw 'The saved BR result did not initialize correctly.'
    }
    if (@($challenges.Id | Select-Object -Unique).Count -ne $challenges.Count) {
        throw 'Challenge IDs must be unique.'
    }
    foreach ($challenge in @($challenges)) {
        if ($challenge.Domain -notin @('Any','Ground','Air','Naval')) { throw "Challenge '$($challenge.Name)' has an invalid domain." }
        if (-not $challenge.PSObject.Properties['FailureAction'] -or $challenge.FailureAction.Type -notin @('None','BRStepsDown','TrackStepsDown')) {
            throw "Challenge '$($challenge.Name)' has an invalid failure action."
        }
    }
    if (@($funModes.Id | Select-Object -Unique).Count -ne $funModes.Count) {
        throw 'Fun-mode IDs must be unique.'
    }
    foreach ($funMode in @($funModes)) {
        if ($funMode.Domain -notin @('Any','Ground','Air','Naval')) { throw "Fun mode '$($funMode.Name)' has an invalid domain." }
    }
    foreach ($domain in @('Ground','Air','Naval')) {
        if (@(Get-EligibleNations $domain).Count -eq 0) { throw "Domain '$domain' must have at least one eligible nation." }
    }
    $validationDomainDirectory = Join-Path ([IO.Path]::GetTempPath()) ("thunder-roulette-domain-{0}" -f [guid]::NewGuid().ToString('N'))
    $originalDirectory = $script:activePaths.Directory
    $originalDomain = [string]$script:activeSettings.Domain
    try {
        New-Item -ItemType Directory -Path $validationDomainDirectory | Out-Null
        $script:activePaths.Directory = $validationDomainDirectory
        $script:activeSettings.Domain = 'Naval'
        $navalRolls = @(1..(@(Get-EligibleNations 'Naval').Count) | ForEach-Object { Get-NextNation })
        if (@($navalRolls | Select-Object -Unique).Count -ne @(Get-EligibleNations 'Naval').Count) { throw 'Naval nation sequence repeated before exhausting its eligibility list.' }
        if (@($navalRolls | Where-Object { $_ -notin @(Get-EligibleNations 'Naval') }).Count -gt 0) { throw 'Naval nation sequence returned an ineligible nation.' }
        $challengeRoll = Get-NextChallenge
        if (-not (Test-ContentDomain $challengeRoll 'Naval')) { throw 'Naval challenge deck returned a challenge for another domain.' }
        $funModeRoll = Get-NextFunMode
        if (-not (Test-ContentDomain $funModeRoll 'Naval')) { throw 'Naval fun-mode deck returned a mode for another domain.' }
    }
    finally {
        $script:activePaths.Directory = $originalDirectory
        $script:activeSettings.Domain = $originalDomain
        if (Test-Path -LiteralPath $validationDomainDirectory) { Remove-Item -LiteralPath $validationDomainDirectory -Recurse -Force }
    }
    if (@($script:progressionCatalog.Tracks).Count -ne 9) {
        throw 'The default progression catalog must contain nine Air/Ground/Naval weapon tracks.'
    }
    foreach ($track in @($script:progressionCatalog.Tracks)) {
        if ($track.Family -notin @('Gun', 'Rocket', 'Missile')) { throw "Invalid progression family '$($track.Family)'." }
        if ($track.Domain -notin @('Air', 'Ground', 'Naval')) { throw "Invalid progression domain '$($track.Domain)'." }
        if (@($track.Stages).Count -eq 0) { throw "Progression track '$($track.Name)' is empty." }
        if (@($track.Stages.Id | Select-Object -Unique).Count -ne @($track.Stages).Count) { throw "Progression stage IDs in '$($track.Name)' must be unique." }
    }
    $validationBRQueue = Join-Path ([IO.Path]::GetTempPath()) ("thunder-roulette-br-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $validationBRBracketQueue = Join-Path ([IO.Path]::GetTempPath()) ("thunder-roulette-br-bracket-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $originalBRQueue = $script:activePaths.BRQueue
    $originalBRBracketQueue = $script:activePaths.BRBracketQueue
    $originalMinimumBR = [double]$script:activeSettings.MinimumBR
    $originalMaximumBR = [double]$script:activeSettings.MaximumBR
    try {
        $script:activePaths.BRQueue = $validationBRQueue
        $script:activePaths.BRBracketQueue = $validationBRBracketQueue
        $script:activeSettings.MinimumBR = 1.0
        $script:activeSettings.MaximumBR = 2.0
        Reset-BRQueue
        $validationBRRolls = @(1..4 | ForEach-Object { Get-NextBR })
        if (@($validationBRRolls | Select-Object -Unique).Count -ne 4) { throw 'BR sequence repeated a stage before exhausting its valid range.' }
        $expectedBRRolls = @(1.0, 1.3, 1.7, 2.0)
        $sortedBRRolls = @($validationBRRolls | Sort-Object)
        for ($index = 0; $index -lt $expectedBRRolls.Count; $index++) {
            if ([math]::Abs([double]$sortedBRRolls[$index] - [double]$expectedBRRolls[$index]) -gt 0.000001) {
                throw 'BR sequence did not contain every valid stage in its range.'
            }
        }
        $script:activeSettings.MinimumBR = 1.3
        $script:activeSettings.MaximumBR = 3.3
        Reset-BRQueue
        $validationBrackets = @(1..3 | ForEach-Object { Get-NextBRBracket })
        if (@($validationBrackets.Id | Select-Object -Unique).Count -ne 3) { throw 'BR bracket sequence repeated before exhausting its valid range.' }
        $sortedBrackets = @($validationBrackets | Sort-Object Minimum)
        $expectedBracketBounds = @(@(1.3,1.7), @(2.0,2.7), @(3.0,3.3))
        for ($index = 0; $index -lt $expectedBracketBounds.Count; $index++) {
            if ([math]::Abs([double]$sortedBrackets[$index].Minimum - [double]$expectedBracketBounds[$index][0]) -gt 0.000001 -or
                [math]::Abs([double]$sortedBrackets[$index].Maximum - [double]$expectedBracketBounds[$index][1]) -gt 0.000001) {
                throw 'BR brackets did not respect the configured profile limits.'
            }
        }
    }
    finally {
        $script:activePaths.BRQueue = $originalBRQueue
        $script:activePaths.BRBracketQueue = $originalBRBracketQueue
        $script:activeSettings.MinimumBR = $originalMinimumBR
        $script:activeSettings.MaximumBR = $originalMaximumBR
        if (Test-Path -LiteralPath $validationBRQueue) { Remove-Item -LiteralPath $validationBRQueue -Force }
        if (Test-Path -LiteralPath $validationBRBracketQueue) { Remove-Item -LiteralPath $validationBRBracketQueue -Force }
    }
    if (-not $rollChallengeButton -or -not $challengeName -or -not $challengeObjective) {
        throw 'Challenge controls did not initialize correctly.'
    }
    if (-not $rollFunModeButton -or -not $funModeName -or -not $funModeRule) {
        throw 'Fun-mode controls did not initialize correctly.'
    }
    if (-not $rollSessionButton -or -not $startSessionButton -or -not $resetAllButton) {
        throw 'Session controls did not initialize correctly.'
    }
    [xml]$validationManageXaml = Get-Content -LiteralPath $manageXamlFile -Raw
    $validationManageReader = [System.Xml.XmlNodeReader]::new($validationManageXaml)
    $validationManageWindow = [Windows.Markup.XamlReader]::Load($validationManageReader)
    foreach ($controlName in @(
        'ManageProfileList', 'ManageMinimumBR', 'ManageMaximumBR', 'ManageBRRollMode', 'ManageResetBRButton',
        'ManageCampaignTrack', 'ManageCampaignStage', 'ManageEligibilityDomain', 'ManageDomainNationPanel', 'RestoreDomainEligibilityButton',
        'SessionRollNation', 'SessionRollBR', 'SessionRollChallenge', 'SessionRollFunMode',
        'ManageProgressionTrack', 'ManageProgressionStageList', 'AddExactStageButton', 'AddRangeStageButton',
        'EditStageButton', 'ToggleStageButton', 'MoveStageUpButton', 'MoveStageDownButton', 'DeleteStageButton', 'RestoreProgressionButton',
        'ManageHistoryList', 'ManageHistorySummary', 'ClearHistoryButton',
        'ManageChallengeList', 'UseSelectedChallengeButton', 'AddChallengeButton', 'EditChallengeButton', 'DeleteChallengeButton', 'ResetChallengeDeckButton', 'RestoreChallengesButton',
        'ManageFunModeList', 'UseSelectedFunModeButton', 'AddFunModeButton', 'EditFunModeButton', 'DeleteFunModeButton', 'ResetFunModeDeckButton', 'RestoreFunModesButton',
        'ManageCloseButton'
    )) {
        if (-not $validationManageWindow.FindName($controlName)) {
            throw "Manage control '$controlName' did not initialize correctly."
        }
    }
    foreach ($windowDefinition in @(
        [pscustomobject]@{
            Path = $challengeEditorXamlFile
            Name = 'Challenge editor'
            Controls = @(
                'ChallengeEditorName', 'ChallengeEditorObjective', 'ChallengeEditorDomain', 'ChallengeEditorTrackers',
                'AddCounterTrackerButton', 'AddCheckboxTrackerButton', 'EditTrackerButton', 'DeleteTrackerButton',
                'ChallengeEditorRecordingMode', 'ChallengeEditorRewardType', 'ChallengeEditorFailureType', 'ChallengeEditorRewardText', 'ChallengeEditorSaveButton', 'ChallengeEditorCancelButton'
            )
        },
        [pscustomobject]@{
            Path = $sessionXamlFile
            Name = 'Session window'
            Controls = @(
                'SessionChallengeName', 'SessionObjective', 'SessionTimer', 'SessionNation', 'SessionBR',
                'SessionFunMode', 'SessionTrack', 'SessionStage', 'SessionReward', 'SessionTrackerScroll', 'SessionTrackerPanel',
                'SessionCampaignCompleteBanner', 'SessionCampaignCompleteText',
                'SessionNotes', 'SessionCompletionHint', 'SessionSuccessButton', 'SessionFailedButton', 'SessionAbandonButton'
            )
        }
    )) {
        [xml]$validationXaml = Get-Content -LiteralPath $windowDefinition.Path -Raw
        $validationReader = [System.Xml.XmlNodeReader]::new($validationXaml)
        $validationWindow = [Windows.Markup.XamlReader]::Load($validationReader)
        foreach ($controlName in $windowDefinition.Controls) {
            if (-not $validationWindow.FindName($controlName)) {
                throw "$($windowDefinition.Name) control '$controlName' did not initialize correctly."
            }
        }
    }
    Write-Output 'Thunder Roulette validation passed.'
    return
}

$null = $window.ShowDialog()
