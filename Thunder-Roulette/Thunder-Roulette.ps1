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
$xamlFile = Join-Path $appRoot 'MainWindow.xaml'
$manageXamlFile = Join-Path $appRoot 'ManageWindow.xaml'

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
    [pscustomobject]@{ Id = 'caliber-climb'; Name = 'Caliber Climb'; Objective = 'Spawn vehicles from your lowest gun caliber to your highest.'; Reward = 'Complete the full lineup order.' }
    [pscustomobject]@{ Id = 'combined-arms'; Name = 'Combined Arms'; Objective = 'Get 2 tank kills and 1 plane kill in the same match.'; Reward = 'Advance one BR stage.' }
    [pscustomobject]@{ Id = 'triple-role'; Name = 'Three Roles'; Objective = 'Earn a kill with three different vehicle classes.'; Reward = 'Advance one BR stage.' }
    [pscustomobject]@{ Id = 'zone-keeper'; Name = 'Zone Keeper'; Objective = 'Capture a zone, then destroy an enemy while defending it.'; Reward = 'Reroll your nation if desired.' }
    [pscustomobject]@{ Id = 'wing-clipper'; Name = 'Wing Clipper'; Objective = 'Destroy an aircraft using a ground vehicle.'; Reward = 'Advance one BR stage.' }
    [pscustomobject]@{ Id = 'one-life'; Name = 'One Life'; Objective = 'Get 3 kills without losing your first vehicle.'; Reward = 'Advance one BR stage.' }
    [pscustomobject]@{ Id = 'support-act'; Name = 'Support Act'; Objective = 'Score 3 assists and help capture at least one zone.'; Reward = 'Failure does not count against the run.' }
    [pscustomobject]@{ Id = 'light-brigade'; Name = 'Light Brigade'; Objective = 'Use only light tanks and tank destroyers for one match.'; Reward = 'Advance one BR stage after a victory.' }
    [pscustomobject]@{ Id = 'heavy-metal'; Name = 'Heavy Metal'; Objective = 'Get 2 kills using a heavy tank without using aircraft.'; Reward = 'Advance one BR stage.' }
    [pscustomobject]@{ Id = 'squad-variety'; Name = 'Squad Variety'; Objective = 'Every squad member must spawn a different vehicle class first.'; Reward = 'Everyone may reroll their BR.' }
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

$defaultChallenges = @($challenges | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Objective = $_.Objective; Reward = $_.Reward } })
$defaultFunModes = @($funModes | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Rule = $_.Rule } })

function Save-ContentLibraries {
    [pscustomobject]@{ Challenges = @($script:challenges); FunModes = @($script:funModes) } |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $contentFile -Encoding UTF8
}

function Load-ContentLibraries {
    try {
        $library = Get-Content -LiteralPath $contentFile -Raw | ConvertFrom-Json
        $loadedChallenges = @($library.Challenges)
        $loadedFunModes = @($library.FunModes)
        if ($loadedChallenges.Count -eq 0 -or $loadedFunModes.Count -eq 0) { throw 'Content libraries cannot be empty.' }
        $script:challenges = $loadedChallenges
        $script:funModes = $loadedFunModes
    }
    catch {
        $script:challenges = @($defaultChallenges)
        $script:funModes = @($defaultFunModes)
        Save-ContentLibraries
    }
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
        $script:challenges = @($defaultChallenges)
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
    $settings = Join-Path $directory 'settings.json'

    if (-not (Test-Path -LiteralPath $queue -PathType Leaf)) {
        New-Item -ItemType File -Path $queue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $challengeQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $challengeQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $funModeQueue -PathType Leaf)) {
        New-Item -ItemType File -Path $funModeQueue | Out-Null
    }
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) {
        @{ ClearSequenceOnExit = $false; MinimumBR = 1.0; MaximumBR = 14.0 } |
            ConvertTo-Json |
            Set-Content -LiteralPath $settings -Encoding UTF8
    }

    return [pscustomobject]@{ Queue = $queue; ChallengeQueue = $challengeQueue; FunModeQueue = $funModeQueue; Settings = $settings }
}

function Get-ProfileSettings {
    try {
        $saved = Get-Content -LiteralPath $script:activePaths.Settings -Raw | ConvertFrom-Json
        $clearOnExit = if ($saved.PSObject.Properties['ClearSequenceOnExit']) { [bool]$saved.ClearSequenceOnExit } else { $false }
        $minimumBR = if ($saved.PSObject.Properties['MinimumBR']) { [double]$saved.MinimumBR } else { 1.0 }
        $maximumBR = if ($saved.PSObject.Properties['MaximumBR']) { [double]$saved.MaximumBR } else { 14.0 }
        return [pscustomobject]@{
            ClearSequenceOnExit = $clearOnExit
            MinimumBR = $minimumBR
            MaximumBR = $maximumBR
        }
    }
    catch {
        return [pscustomobject]@{ ClearSequenceOnExit = $false; MinimumBR = 1.0; MaximumBR = 14.0 }
    }
}

function Save-ProfileSettings([bool] $clearSequenceOnExit, [double] $minimumBR, [double] $maximumBR) {
    @{
        ClearSequenceOnExit = $clearSequenceOnExit
        MinimumBR = $minimumBR
        MaximumBR = $maximumBR
    } |
        ConvertTo-Json |
        Set-Content -LiteralPath $script:activePaths.Settings -Encoding UTF8
}

function Reset-NationQueue {
    Set-Content -LiteralPath $script:activePaths.Queue -Value ([string[]]@()) -Encoding UTF8
}

function New-NationQueue {
    $shuffledNations = @($nations.Keys | Get-Random -Count $nations.Count)
    Set-Content -LiteralPath $script:activePaths.Queue -Value $shuffledNations -Encoding UTF8
    return $shuffledNations
}

function Get-NextNation {
    $queue = @(
        Get-Content -LiteralPath $script:activePaths.Queue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-NationQueue)
    }

    $selectedNation = $queue[0]
    Set-Content -LiteralPath $script:activePaths.Queue -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return $selectedNation
}

function New-ChallengeQueue {
    $shuffledIds = @($challenges.Id | Get-Random -Count $challenges.Count)
    Set-Content -LiteralPath $script:activePaths.ChallengeQueue -Value $shuffledIds -Encoding UTF8
    return $shuffledIds
}

function Get-NextChallenge {
    $queue = @(
        Get-Content -LiteralPath $script:activePaths.ChallengeQueue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -in $challenges.Id }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-ChallengeQueue)
    }

    $selectedId = $queue[0]
    Set-Content -LiteralPath $script:activePaths.ChallengeQueue -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
    return @($challenges | Where-Object Id -eq $selectedId)[0]
}

function New-FunModeQueue {
    $shuffledIds = @($funModes.Id | Get-Random -Count $funModes.Count)
    Set-Content -LiteralPath $script:activePaths.FunModeQueue -Value $shuffledIds -Encoding UTF8
    return $shuffledIds
}

function Get-NextFunMode {
    $queue = @(
        Get-Content -LiteralPath $script:activePaths.FunModeQueue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -in $funModes.Id }
    )
    if ($queue.Count -eq 0) {
        $queue = @(New-FunModeQueue)
    }

    $selectedId = $queue[0]
    Set-Content -LiteralPath $script:activePaths.FunModeQueue -Value @($queue | Select-Object -Skip 1) -Encoding UTF8
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

Initialize-AppData
Load-ContentLibraries

[xml]$xaml = Get-Content -LiteralPath $xamlFile -Raw
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$profileSelector = $window.FindName('ProfileSelector')
$manageButton = $window.FindName('ManageButton')
$rollButton = $window.FindName('RollButton')
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
        Get-Content -LiteralPath $script:activePaths.Queue |
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
        Get-Content -LiteralPath $script:activePaths.ChallengeQueue |
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
        Get-Content -LiteralPath $script:activePaths.FunModeQueue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count
    $funModeRemainingText.Text = if ($remaining -eq 0) {
        'A fresh fun-mode deck will begin on the next draw'
    }
    else {
        "$remaining mode$(if ($remaining -ne 1) { 's' }) left in this deck"
    }
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
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    $brRangeText.Text = ('Range {0:N1}-{1:N1}' -f $script:activeSettings.MinimumBR, $script:activeSettings.MaximumBR)
    $nationName.Text = 'Ready?'
    $brResult.Text = [string][char]0x2014
    $challengeName.Text = 'No challenge drawn'
    $challengeObjective.Text = 'Draw a challenge when your squad is feeling brave.'
    $challengeReward.Text = ''
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
    $manageClearOnExit = $manageWindow.FindName('ManageClearOnExit')
    $manageChallengeList = $manageWindow.FindName('ManageChallengeList')
    $manageFunModeList = $manageWindow.FindName('ManageFunModeList')
    $addChallengeButton = $manageWindow.FindName('AddChallengeButton')
    $editChallengeButton = $manageWindow.FindName('EditChallengeButton')
    $deleteChallengeButton = $manageWindow.FindName('DeleteChallengeButton')
    $restoreChallengesButton = $manageWindow.FindName('RestoreChallengesButton')
    $addFunModeButton = $manageWindow.FindName('AddFunModeButton')
    $editFunModeButton = $manageWindow.FindName('EditFunModeButton')
    $deleteFunModeButton = $manageWindow.FindName('DeleteFunModeButton')
    $restoreFunModesButton = $manageWindow.FindName('RestoreFunModesButton')
    $resetChallengeDeckButton = $manageWindow.FindName('ResetChallengeDeckButton')
    $resetFunModeDeckButton = $manageWindow.FindName('ResetFunModeDeckButton')
    $manageCloseButton = $manageWindow.FindName('ManageCloseButton')

    $manageMinimumBR.ItemsSource = $brStages
    $manageMaximumBR.ItemsSource = $brStages
    $script:manageChanging = $false

    $refreshContentLists = {
        param([string] $challengeId, [string] $funModeId)
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

    $loadManageSettings = {
        $script:manageChanging = $true
        $manageMinimumBR.SelectedItem = [double]$script:activeSettings.MinimumBR
        $manageMaximumBR.SelectedItem = [double]$script:activeSettings.MaximumBR
        $manageClearOnExit.IsChecked = [bool]$script:activeSettings.ClearSequenceOnExit
        $script:manageChanging = $false
    }

    $saveManageSettings = {
        if ($script:manageChanging) { return }
        if ([double]$manageMinimumBR.SelectedItem -gt [double]$manageMaximumBR.SelectedItem) {
            $script:manageChanging = $true
            $manageMaximumBR.SelectedItem = $manageMinimumBR.SelectedItem
            $script:manageChanging = $false
        }
        $script:activeSettings.MinimumBR = [double]$manageMinimumBR.SelectedItem
        $script:activeSettings.MaximumBR = [double]$manageMaximumBR.SelectedItem
        $script:activeSettings.ClearSequenceOnExit = [bool]$manageClearOnExit.IsChecked
        Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
        $brRangeText.Text = ('Range {0:N1}-{1:N1}' -f $script:activeSettings.MinimumBR, $script:activeSettings.MaximumBR)
    }

    & $refreshManageProfiles $script:activeProfileId
    & $loadManageSettings
    & $refreshContentLists $null $null

    $manageProfileList.Add_SelectionChanged({
        if ($manageProfileList.SelectedValue -and $manageProfileList.SelectedValue -ne $script:activeProfileId) {
            & $setActiveProfile ([string]$manageProfileList.SelectedValue)
            & $refreshProfileSelector $script:activeProfileId
            & $loadManageSettings
        }
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
    $manageMaximumBR.Add_SelectionChanged({
        if (-not $script:manageChanging -and [double]$manageMaximumBR.SelectedItem -lt [double]$manageMinimumBR.SelectedItem) {
            $script:manageChanging = $true
            $manageMinimumBR.SelectedItem = $manageMaximumBR.SelectedItem
            $script:manageChanging = $false
        }
        & $saveManageSettings
    })
    $manageClearOnExit.Add_Click({ & $saveManageSettings })

    $addChallengeButton.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Challenge name:', 'Add challenge', '').Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $objective = [Microsoft.VisualBasic.Interaction]::InputBox('What must the player accomplish?', 'Challenge objective', '').Trim()
        if ([string]::IsNullOrWhiteSpace($objective)) { return }
        $reward = [Microsoft.VisualBasic.Interaction]::InputBox('What happens on success?', 'Challenge reward', 'Complete the challenge.').Trim()
        if ([string]::IsNullOrWhiteSpace($reward)) { return }
        $card = [pscustomobject]@{ Id = 'custom-' + [guid]::NewGuid().ToString('N'); Name = $name; Objective = $objective; Reward = $reward }
        $script:challenges = @($script:challenges) + $card
        Save-ContentLibraries
        & $refreshContentLists $card.Id $null
    })

    $editChallengeButton.Add_Click({
        $card = $manageChallengeList.SelectedItem
        if (-not $card) { return }
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Challenge name:', 'Edit challenge', $card.Name).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $objective = [Microsoft.VisualBasic.Interaction]::InputBox('What must the player accomplish?', 'Challenge objective', $card.Objective).Trim()
        if ([string]::IsNullOrWhiteSpace($objective)) { return }
        $reward = [Microsoft.VisualBasic.Interaction]::InputBox('What happens on success?', 'Challenge reward', $card.Reward).Trim()
        if ([string]::IsNullOrWhiteSpace($reward)) { return }
        $card.Name = $name; $card.Objective = $objective; $card.Reward = $reward
        Save-ContentLibraries
        & $refreshContentLists $card.Id $null
    })

    $deleteChallengeButton.Add_Click({
        $card = $manageChallengeList.SelectedItem
        if (-not $card -or @($script:challenges).Count -le 1) { return }
        if ([System.Windows.MessageBox]::Show("Delete challenge '$($card.Name)'?", 'Delete challenge', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:challenges = @($script:challenges | Where-Object Id -ne $card.Id)
        Save-ContentLibraries
        & $refreshContentLists $null $null
    })

    $addFunModeButton.Add_Click({
        $name = [Microsoft.VisualBasic.Interaction]::InputBox('Fun-mode name:', 'Add fun mode', '').Trim()
        if ([string]::IsNullOrWhiteSpace($name)) { return }
        $rule = [Microsoft.VisualBasic.Interaction]::InputBox('What lineup or playstyle rule applies?', 'Fun-mode rule', '').Trim()
        if ([string]::IsNullOrWhiteSpace($rule)) { return }
        $card = [pscustomobject]@{ Id = 'custom-' + [guid]::NewGuid().ToString('N'); Name = $name; Rule = $rule }
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
        $card.Name = $name; $card.Rule = $rule
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
        $script:challenges = @($defaultChallenges | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Objective = $_.Objective; Reward = $_.Reward } })
        Save-ContentLibraries
        Clear-Content -LiteralPath $script:activePaths.ChallengeQueue
        & $refreshContentLists $null $null
        & $updateChallengeRemainingText
    })

    $restoreFunModesButton.Add_Click({
        if ([System.Windows.MessageBox]::Show('Replace all fun modes with the shipped defaults?', 'Restore fun modes', [System.Windows.MessageBoxButton]::YesNo) -ne [System.Windows.MessageBoxResult]::Yes) { return }
        $script:funModes = @($defaultFunModes | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.Name; Rule = $_.Rule } })
        Save-ContentLibraries
        Clear-Content -LiteralPath $script:activePaths.FunModeQueue
        & $refreshContentLists $null $null
        & $updateFunModeRemainingText
    })

    $resetChallengeDeckButton.Add_Click({ Clear-Content -LiteralPath $script:activePaths.ChallengeQueue; & $updateChallengeRemainingText })
    $resetFunModeDeckButton.Add_Click({ Clear-Content -LiteralPath $script:activePaths.FunModeQueue; & $updateFunModeRemainingText })
    $manageCloseButton.Add_Click({ $manageWindow.Close() })

    $null = $manageWindow.ShowDialog()
})

$rollButton.Add_Click({
    $selectedNation = Get-NextNation
    $nationName.Text = $selectedNation
    $nationImage.Source = New-BitmapImage (Join-Path $appRoot "Assets\NationIcons\$($nations[$selectedNation])")
    & $updateRemainingText
})

$resetButton.Add_Click({
    Reset-NationQueue
    $nationName.Text = 'Ready?'
    $nationImage.Source = New-BitmapImage $emptyImagePath
    & $updateRemainingText
})

$rollBRButton.Add_Click({
    $availableStages = @($brStages | Where-Object {
        $_ -ge [double]$script:activeSettings.MinimumBR -and
        $_ -le [double]$script:activeSettings.MaximumBR
    })
    $brResult.Text = ('{0:N1}' -f ($availableStages | Get-Random))
})

$rollChallengeButton.Add_Click({
    $challenge = Get-NextChallenge
    $challengeName.Text = $challenge.Name
    $challengeObjective.Text = $challenge.Objective
    $challengeReward.Text = "SUCCESS: $($challenge.Reward)"
    & $updateChallengeRemainingText
})

$rollFunModeButton.Add_Click({
    $funMode = Get-NextFunMode
    $funModeName.Text = $funMode.Name
    $funModeRule.Text = $funMode.Rule
    & $updateFunModeRemainingText
})

$window.Add_Closed({
    Save-ProfileSettings ([bool]$script:activeSettings.ClearSequenceOnExit) ([double]$script:activeSettings.MinimumBR) ([double]$script:activeSettings.MaximumBR)
    if ([bool]$script:activeSettings.ClearSequenceOnExit) {
        Reset-NationQueue
    }
})

if ($ValidateOnly) {
    if ($brResult.Text -ne [string][char]0x2014) {
        throw 'The BR placeholder did not initialize correctly.'
    }
    if (@($challenges.Id | Select-Object -Unique).Count -ne $challenges.Count) {
        throw 'Challenge IDs must be unique.'
    }
    if (@($funModes.Id | Select-Object -Unique).Count -ne $funModes.Count) {
        throw 'Fun-mode IDs must be unique.'
    }
    if (-not $rollChallengeButton -or -not $challengeName -or -not $challengeObjective) {
        throw 'Challenge controls did not initialize correctly.'
    }
    if (-not $rollFunModeButton -or -not $funModeName -or -not $funModeRule) {
        throw 'Fun-mode controls did not initialize correctly.'
    }
    [xml]$validationManageXaml = Get-Content -LiteralPath $manageXamlFile -Raw
    $validationManageReader = [System.Xml.XmlNodeReader]::new($validationManageXaml)
    $validationManageWindow = [Windows.Markup.XamlReader]::Load($validationManageReader)
    foreach ($controlName in @(
        'ManageProfileList', 'ManageMinimumBR', 'ManageMaximumBR',
        'ManageChallengeList', 'AddChallengeButton', 'EditChallengeButton', 'DeleteChallengeButton', 'RestoreChallengesButton',
        'ManageFunModeList', 'AddFunModeButton', 'EditFunModeButton', 'DeleteFunModeButton', 'RestoreFunModesButton',
        'ManageCloseButton'
    )) {
        if (-not $validationManageWindow.FindName($controlName)) {
            throw "Manage control '$controlName' did not initialize correctly."
        }
    }
    Write-Output 'Thunder Roulette validation passed.'
    return
}

$null = $window.ShowDialog()
