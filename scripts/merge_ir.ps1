param(
    [string]$RawDataPath = "raw_data",
    [string]$OutputPath = "processed\merged_ir.csv"
)

$ErrorActionPreference = "Stop"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture
$rawRoot = (Resolve-Path -LiteralPath $RawDataPath).Path

$dataHeaders = @(
    "ELAPSED_TIME",
    "TPROC",
    "TINT",
    "TBOX",
    "TAVG",
    "T_2C",
    "T_1C",
    "ATTENUATION",
    "EPS",
    "VALUE",
    "VCC",
    "TAMB",
    "TACT",
    "COMPRESSION_IDX",
    "TIME_ABSOLUTE",
    "IMAGE_IDX",
    "IMAGE_VALUE"
)

function Normalize-Decimal([string]$value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }
    return $value.Trim().Replace(",", ".")
}

function Get-MetadataValue([string[]]$lines, [string]$name) {
    $prefix = "${name}:"
    $line = $lines | Where-Object { $_.StartsWith($prefix) } | Select-Object -First 1
    if ($null -eq $line) { return "" }
    return $line.Substring($prefix.Length).Trim()
}

function Get-DetailedTimestamp(
    [string]$sessionDate,
    [string]$sessionTime,
    [string]$elapsedTime,
    [string]$absoluteTime
) {
    $base = [datetime]::ParseExact(
        "$sessionDate $sessionTime",
        "dd/MM/yyyy HH:mm:ss",
        $invariant
    )

    if ($elapsedTime -notmatch '^(?<hours>\d{3}):(?<minutes>\d{2}):(?<seconds>\d{2}),(?<milliseconds>\d{3})$') {
        throw "Invalid elapsed time: $elapsedTime"
    }
    $elapsedHours = [int]$matches["hours"]
    $elapsedMinutes = [int]$matches["minutes"]
    $elapsedSeconds = [int]$matches["seconds"]
    $elapsedMilliseconds = [int]$matches["milliseconds"]

    $absoluteMilliseconds = 0
    if ($absoluteTime -match '^\d{2}:\d{2}:\d{2}:(?<milliseconds>\d{3})$') {
        $absoluteMilliseconds = [int]$matches["milliseconds"]
    }

    $timestamp = $base.AddHours($elapsedHours)
    $timestamp = $timestamp.AddMinutes($elapsedMinutes)
    $timestamp = $timestamp.AddSeconds($elapsedSeconds)
    $timestamp = $timestamp.AddMilliseconds($elapsedMilliseconds + $absoluteMilliseconds)
    return $timestamp.ToString("yyyy-MM-dd HH:mm:ss.fff", $invariant)
}

function New-SourceSet {
    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    return ,$set
}

$detailedRecords = @{}
$simpleRecords = @{}
$detailedInputRows = 0
$simpleInputRows = 0

$datFiles = Get-ChildItem -LiteralPath $rawRoot -File -Filter "*.dat" |
    Where-Object { $_.Name -match '(?i)IR' } |
    Sort-Object Name

foreach ($file in $datFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    $sessionDate = Get-MetadataValue $lines "Date"
    $sessionTime = Get-MetadataValue $lines "Time"
    $unit = Get-MetadataValue $lines "Unit"
    $resolution = Get-MetadataValue $lines "Resolution"
    $valuesCount = Get-MetadataValue $lines "Values"
    $snapshotTrigger = Get-MetadataValue $lines "SnapshotTrigger"
    $measurementTrigger = Get-MetadataValue $lines "MeasurementTrigger"

    foreach ($line in $lines) {
        if ($line -notmatch '^\d{3}:\d{2}:\d{2},\d{3}\t') { continue }
        $parts = $line.Split([char]9)
        if ($parts.Count -ne 17) {
            throw "Expected 17 fields in $($file.Name), found $($parts.Count): $line"
        }

        $detailedInputRows++
        $sessionKey = "$sessionDate|$sessionTime"
        $recordKey = "$sessionKey|$line"
        if ($detailedRecords.ContainsKey($recordKey)) {
            [void]$detailedRecords[$recordKey].Sources.Add($file.Name)
            continue
        }

        $timestamp = Get-DetailedTimestamp $sessionDate $sessionTime $parts[0] $parts[14]
        $values = @()
        for ($index = 0; $index -lt $parts.Count; $index++) {
            if ($index -eq 0) {
                $values += $parts[$index].Replace(",", ".").Trim()
            } elseif ($index -eq 14) {
                $values += $parts[$index].Trim()
            } else {
                $values += Normalize-Decimal $parts[$index]
            }
        }

        $sources = New-SourceSet
        [void]$sources.Add($file.Name)
        $detailedRecords[$recordKey] = [PSCustomObject]@{
            Timestamp = $timestamp
            Values = $values
            SessionDate = $sessionDate
            SessionTime = $sessionTime
            Unit = $unit
            Resolution = $resolution
            ValuesCount = $valuesCount
            SnapshotTrigger = $snapshotTrigger
            MeasurementTrigger = $measurementTrigger
            Sources = $sources
        }
    }
}

$txtFiles = Get-ChildItem -LiteralPath $rawRoot -File -Filter "*.txt" |
    Where-Object { $_.Name -match '(?i)IR' } |
    Sort-Object Name

$simplePattern = '^(?<date>\d{4}-\d{2}-\d{2})\s+(?<time>\d{2}:\d{2}:\d{2})\s+(?<temperature>[+-]?\d+,\d+)\s*$'
foreach ($file in $txtFiles) {
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        if ($line -notmatch $simplePattern) { continue }
        $simpleInputRows++
        $timestamp = "$($matches['date']) $($matches['time']).000"
        $temperature = Normalize-Decimal $matches["temperature"]
        $recordKey = "$timestamp|$temperature"

        if ($simpleRecords.ContainsKey($recordKey)) {
            [void]$simpleRecords[$recordKey].Sources.Add($file.Name)
            continue
        }

        $sources = New-SourceSet
        [void]$sources.Add($file.Name)
        $simpleRecords[$recordKey] = [PSCustomObject]@{
            Timestamp = $timestamp
            Temperature = $temperature
            Sources = $sources
        }
    }
}

$outputRows = [System.Collections.Generic.List[object]]::new()

foreach ($record in $detailedRecords.Values) {
    $row = [ordered]@{
        RECORD_TYPE = "DETAILED_DAT"
        TIMESTAMP = $record.Timestamp
        TEMPERATURE_C = ""
    }
    for ($index = 0; $index -lt $dataHeaders.Count; $index++) {
        $row[$dataHeaders[$index]] = $record.Values[$index]
    }
    $row["SESSION_DATE"] = $record.SessionDate
    $row["SESSION_TIME"] = $record.SessionTime
    $row["UNIT"] = $record.Unit
    $row["RESOLUTION"] = $record.Resolution
    $row["VALUES_COUNT"] = $record.ValuesCount
    $row["SNAPSHOT_TRIGGER"] = $record.SnapshotTrigger
    $row["MEASUREMENT_TRIGGER"] = $record.MeasurementTrigger
    $sourceNames = @($record.Sources) | Sort-Object
    $row["SOURCE_FILES"] = $sourceNames -join ";"
    $row["SOURCE_FILE_COUNT"] = $sourceNames.Count
    $outputRows.Add([PSCustomObject]$row)
}

foreach ($record in $simpleRecords.Values) {
    $row = [ordered]@{
        RECORD_TYPE = "SIMPLE_TXT"
        TIMESTAMP = $record.Timestamp
        TEMPERATURE_C = $record.Temperature
    }
    foreach ($header in $dataHeaders) { $row[$header] = "" }
    $row["SESSION_DATE"] = ""
    $row["SESSION_TIME"] = ""
    $row["UNIT"] = "degC"
    $row["RESOLUTION"] = ""
    $row["VALUES_COUNT"] = ""
    $row["SNAPSHOT_TRIGGER"] = ""
    $row["MEASUREMENT_TRIGGER"] = ""
    $sourceNames = @($record.Sources) | Sort-Object
    $row["SOURCE_FILES"] = $sourceNames -join ";"
    $row["SOURCE_FILE_COUNT"] = $sourceNames.Count
    $outputRows.Add([PSCustomObject]$row)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$outputRows |
    Sort-Object TIMESTAMP, RECORD_TYPE |
    Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

[PSCustomObject]@{
    DetailedFiles = $datFiles.Count
    SimpleFiles = $txtFiles.Count
    DetailedInputRows = $detailedInputRows
    DetailedUniqueRows = $detailedRecords.Count
    DetailedDuplicateOccurrences = $detailedInputRows - $detailedRecords.Count
    SimpleInputRows = $simpleInputRows
    SimpleUniqueRows = $simpleRecords.Count
    SimpleDuplicateOccurrences = $simpleInputRows - $simpleRecords.Count
    OutputRows = $outputRows.Count
    OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
}
