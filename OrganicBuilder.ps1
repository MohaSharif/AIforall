<#
.SYNOPSIS
OrganicBuilderCLI - تطبيق تفاعلي لتدريب طلاب الصف الحادي عشر على المجموعات الوظيفية في الكيمياء العضوية.

.DESCRIPTION
يوفر أوضاع تدريب على: التعرف على المجموعة الوظيفية، التسمية المبسطة، مقارنة الخواص،
وبناء بطاقة تفسير لصيغة مكثفة. يحفظ التقدم في ملف JSON محلي.

.USAGE
powershell -ExecutionPolicy Bypass -File .\OrganicBuilder.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Color-Write {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::White,
        [switch]$NoNewLine
    )
    if ($NoNewLine) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    } else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Normalize-Input {
    param([string]$Text)
    if (-not $Text) { return '' }
    $n = $Text.Trim().ToUpper()
    $n = $n -replace '\s+', ''
    return $n
}

function Read-NonEmpty {
    param([string]$Prompt)
    while ($true) {
        $v = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($v)) { return $v.Trim() }
        Color-Write 'المدخل فارغ. حاول مرة أخرى.' Yellow
    }
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$ValidChoices
    )
    while ($true) {
        $v = Read-Host $Prompt
        if ($ValidChoices -contains $v) { return $v }
        Color-Write ("خيار غير صالح. الخيارات المتاحة: {0}" -f ($ValidChoices -join ', ')) Yellow
    }
}

function Pick-RandomDistinct {
    param(
        [array]$Items,
        [int]$Count
    )
    if ($Count -gt $Items.Count) { throw 'لا يمكن اختيار عناصر أكثر من حجم القائمة.' }
    return $Items | Get-Random -Count $Count
}

function Get-FamilyLabelAr {
    param([string]$Family)
    switch ($Family) {
        'alkyl_halide' { 'هاليد ألكيل' }
        'alcohol' { 'كحول' }
        'aldehyde' { 'ألدهيد' }
        'ketone' { 'كيتون' }
        'carboxylic_acid' { 'حمض كربوكسيلي' }
        default { 'غير معروف' }
    }
}

function Get-HighlightFormula {
    param(
        [string]$Formula,
        [string]$Family
    )
    switch ($Family) {
        'carboxylic_acid' { return ($Formula -replace 'COOH', '[COOH]') }
        'aldehyde' { return ($Formula -replace 'CHO', '[CHO]') }
        'ketone' {
            if ($Formula -match 'C\(=O\)') { return ($Formula -replace 'C\(=O\)', '[C(=O)]') }
            if ($Formula -match 'CO') { return ($Formula -replace 'CO', '[CO]') }
            return $Formula
        }
        'alcohol' { return ($Formula -replace 'OH', '[OH]') }
        'alkyl_halide' {
            if ($Formula -match 'CL') { return ($Formula -replace 'CL', '[Cl]') }
            if ($Formula -match 'BR') { return ($Formula -replace 'BR', '[Br]') }
            if ($Formula -match 'F') { return ($Formula -replace 'F', '[F]') }
            if ($Formula -match 'I') { return ($Formula -replace 'I', '[I]') }
            return $Formula
        }
        default { return $Formula }
    }
}

function Estimate-Properties {
    param(
        [string]$Family,
        [int]$Carbons
    )
    $polarity = 'medium'; $hbond = $false; $water = 'low'; $bp = 'medium'
    switch ($Family) {
        'carboxylic_acid' {
            $polarity = 'high'; $hbond = $true; $bp = 'high'
            if ($Carbons -le 3) { $water = 'high' } elseif ($Carbons -le 5) { $water = 'medium' } else { $water = 'low' }
        }
        'alcohol' {
            $polarity = 'high'; $hbond = $true; $bp = if ($Carbons -le 2) { 'medium' } else { 'high' }
            if ($Carbons -le 3) { $water = 'high' } elseif ($Carbons -eq 4) { $water = 'medium' } else { $water = 'low' }
        }
        'aldehyde' {
            $polarity = 'medium'; $hbond = $false; $bp = if ($Carbons -le 3) { 'medium' } else { 'high' }
            if ($Carbons -le 3) { $water = 'high' } elseif ($Carbons -le 5) { $water = 'medium' } else { $water = 'low' }
        }
        'ketone' {
            $polarity = 'medium'; $hbond = $false; $bp = if ($Carbons -le 4) { 'medium' } else { 'high' }
            if ($Carbons -le 4) { $water = 'high' } elseif ($Carbons -eq 5) { $water = 'medium' } else { $water = 'low' }
        }
        'alkyl_halide' {
            $polarity = 'medium'; $hbond = $false
            if ($Carbons -le 2) { $water = 'medium'; $bp = 'low' }
            elseif ($Carbons -le 4) { $water = 'low'; $bp = 'medium' }
            else { $water = 'low'; $bp = 'high' }
        }
    }
    return [ordered]@{ polarity = $polarity; hbond = $hbond; water_solubility = $water; bp_relative = $bp }
}

function Classify-Formula {
    param([string]$Formula)
    $f = Normalize-Input $Formula
    if ($f -match 'COOH') { return 'carboxylic_acid' }
    if ($f -match 'CHO' -or $f -match 'CH=O$' -or $f -match 'C\(=O\)H') { return 'aldehyde' }

    $carbonCount = ([regex]::Matches($f, 'C')).Count
    if (($f -match 'C\(=O\)' -or $f -match '.+CO.+') -and $carbonCount -ge 3 -and -not ($f -match 'COOH') -and -not ($f -match 'CHO$')) {
        return 'ketone'
    }

    if ($f -match 'OH' -and -not ($f -match 'COOH')) { return 'alcohol' }
    if ($f -match 'CL|BR|\bF\b|I') { return 'alkyl_halide' }
    return 'unknown'
}

function Compute-Reasoning {
    param(
        [hashtable]$Mol,
        [string]$Property
    )
    $familyAr = Get-FamilyLabelAr $Mol.family
    $c = [int]$Mol.chain_carbons
    switch ($Property) {
        'water_solubility' {
            return "$familyAr: وجود المجموعة الوظيفية يحدد ذوبانية الماء. كلما زادت السلسلة الكربونية ($c C) تقل الذوبانية غالبًا."
        }
        'bp_relative' {
            return "$familyAr: الروابط الهيدروجينية ترفع درجة الغليان، كما أن زيادة طول السلسلة الكربونية ترفعها نسبيًا."
        }
        'polarity' {
            return "$familyAr: نوع المجموعة الوظيفية هو العامل الأساسي في القطبية، ثم تأثير طول السلسلة."
        }
        default {
            return "تعتمد المقارنة على نوع المجموعة الوظيفية وطول السلسلة الكربونية."
        }
    }
}

function New-ProgressObject {
    return [ordered]@{
        total_answered = 0
        correct_answers = 0
        mode_stats = @{}
        family_stats = @{}
        mistakes = @{}
        last_active_date = (Get-Date -Format 'yyyy-MM-dd')
        streak_days = 1
        settings = [ordered]@{
            difficulty = 'متوسط'
            question_count = 10
            timer_seconds = 0
        }
    }
}

function Initialize-App {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $basePath = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $basePath) { $basePath = (Get-Location).Path }

    $dataDir = Join-Path $basePath 'data'
    $userDir = Join-Path $basePath 'user'
    foreach ($d in @($dataDir, $userDir)) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d | Out-Null
        }
    }

    $datasetPath = Join-Path $dataDir 'molecules.json'
    $progressPath = Join-Path $userDir 'progress.json'
    return [ordered]@{ base = $basePath; dataset = $datasetPath; progress = $progressPath }
}

function Load-Dataset {
    param([string]$DatasetPath)
    if (-not (Test-Path $DatasetPath)) {
        throw 'ملف البيانات غير موجود: data/molecules.json'
    }
    try {
        $raw = Get-Content -Path $DatasetPath -Raw -Encoding UTF8
        $data = $raw | ConvertFrom-Json
        return @($data)
    } catch {
        throw "تعذر قراءة ملف البيانات: $($_.Exception.Message)"
    }
}

function Load-Progress {
    param([string]$ProgressPath)
    if (-not (Test-Path $ProgressPath)) {
        $p = New-ProgressObject
        Save-Progress -ProgressPath $ProgressPath -Progress $p
        return $p
    }
    try {
        $raw = Get-Content -Path $ProgressPath -Raw -Encoding UTF8
        $p = $raw | ConvertFrom-Json -AsHashtable
        if (-not $p.settings) { $p.settings = (New-ProgressObject).settings }
        return $p
    } catch {
        Color-Write "ملف التقدم تالف. سيتم إنشاء ملف جديد. السبب: $($_.Exception.Message)" Yellow
        $p = New-ProgressObject
        Save-Progress -ProgressPath $ProgressPath -Progress $p
        return $p
    }
}

function Save-Progress {
    param(
        [string]$ProgressPath,
        [hashtable]$Progress
    )
    try {
        $json = $Progress | ConvertTo-Json -Depth 8
        Set-Content -Path $ProgressPath -Value $json -Encoding UTF8
    } catch {
        Color-Write "تعذر حفظ التقدم: $($_.Exception.Message)" Red
    }
}

function Update-Streak {
    param([hashtable]$Progress)
    $today = Get-Date -Format 'yyyy-MM-dd'
    $last = [string]$Progress.last_active_date
    if ($last -eq $today) { return }

    $dToday = [datetime]::ParseExact($today, 'yyyy-MM-dd', $null)
    $dLast = [datetime]::ParseExact($last, 'yyyy-MM-dd', $null)
    $diff = ($dToday - $dLast).Days
    if ($diff -eq 1) { $Progress.streak_days = [int]$Progress.streak_days + 1 }
    elseif ($diff -gt 1) { $Progress.streak_days = 1 }
    $Progress.last_active_date = $today
}

function Update-Stats {
    param(
        [hashtable]$Progress,
        [string]$Mode,
        [string]$Family,
        [bool]$IsCorrect,
        [string]$MoleculeId
    )
    $Progress.total_answered = [int]$Progress.total_answered + 1
    if ($IsCorrect) { $Progress.correct_answers = [int]$Progress.correct_answers + 1 }

    if (-not $Progress.mode_stats.ContainsKey($Mode)) {
        $Progress.mode_stats[$Mode] = [ordered]@{ total = 0; correct = 0 }
    }
    $Progress.mode_stats[$Mode].total = [int]$Progress.mode_stats[$Mode].total + 1
    if ($IsCorrect) { $Progress.mode_stats[$Mode].correct = [int]$Progress.mode_stats[$Mode].correct + 1 }

    if (-not $Progress.family_stats.ContainsKey($Family)) {
        $Progress.family_stats[$Family] = [ordered]@{ total = 0; correct = 0 }
    }
    $Progress.family_stats[$Family].total = [int]$Progress.family_stats[$Family].total + 1
    if ($IsCorrect) { $Progress.family_stats[$Family].correct = [int]$Progress.family_stats[$Family].correct + 1 }

    if (-not $IsCorrect -and $MoleculeId) {
        if (-not $Progress.mistakes.ContainsKey($MoleculeId)) { $Progress.mistakes[$MoleculeId] = 0 }
        $Progress.mistakes[$MoleculeId] = [int]$Progress.mistakes[$MoleculeId] + 1
    }
}

function Get-QuestionCount {
    param([hashtable]$Progress)
    $q = [int]$Progress.settings.question_count
    if ($q -lt 1) { return 10 }
    return $q
}

function Mode-Identify {
    param([array]$Dataset, [hashtable]$Progress)
    Color-Write "`n=== وضع التدريب السريع: اكتشاف المجموعة الوظيفية ===" Cyan
    $families = @('alkyl_halide', 'alcohol', 'aldehyde', 'ketone', 'carboxylic_acid')
    $labels = @('1) هاليد ألكيل', '2) كحول', '3) ألدهيد', '4) كيتون', '5) حمض كربوكسيلي')
    $count = Get-QuestionCount $Progress

    for ($i = 1; $i -le $count; $i++) {
        $m = $Dataset | Get-Random
        Color-Write ("`nسؤال {0}/{1} - الصيغة: {2}" -f $i, $count, $m.display_formula) White
        $labels | ForEach-Object { Color-Write $_ DarkGray }
        $ans = Read-Choice -Prompt 'اختر الرقم الصحيح' -ValidChoices @('1', '2', '3', '4', '5')
        $idx = [int]$ans - 1
        $choiceFamily = $families[$idx]
        $ok = $choiceFamily -eq $m.family
        if ($ok) {
            Color-Write '✅ صحيح!' Green
        } else {
            Color-Write ("❌ غير صحيح. الإجابة: {0}" -f (Get-FamilyLabelAr $m.family)) Red
        }
        Color-Write ("تفسير: {0}" -f $m.notes_ar) Yellow
        Update-Stats -Progress $Progress -Mode 'identify' -Family $m.family -IsCorrect:$ok -MoleculeId $m.id
    }
}

function Mode-NameIt {
    param([array]$Dataset, [hashtable]$Progress)
    Color-Write "`n=== وضع التسمية المبسطة: Name-It ===" Cyan
    $count = Get-QuestionCount $Progress

    for ($i = 1; $i -le $count; $i++) {
        $m = $Dataset | Get-Random
        $sameFamily = @($Dataset | Where-Object { $_.family -eq $m.family -and $_.id -ne $m.id })
        $other = @($Dataset | Where-Object { $_.family -ne $m.family })

        $opts = @($m)
        $opts += Pick-RandomDistinct -Items $sameFamily -Count 1
        $opts += Pick-RandomDistinct -Items $other -Count 2
        $opts = $opts | Sort-Object { Get-Random }

        Color-Write ("`nسؤال {0}/{1} - ما اسم المركب؟ {2}" -f $i, $count, $m.display_formula) White
        for ($k = 0; $k -lt $opts.Count; $k++) {
            Color-Write ("{0}) {1}" -f ($k + 1), $opts[$k].name_ar) DarkGray
        }

        $ans = Read-Choice -Prompt 'اختر الرقم الصحيح' -ValidChoices @('1', '2', '3', '4')
        $chosen = $opts[[int]$ans - 1]
        $ok = $chosen.id -eq $m.id

        if ($ok) {
            Color-Write '✅ ممتاز! اختيارك صحيح.' Green
        } else {
            Color-Write ("❌ الصحيح هو: {0}" -f $m.name_ar) Red
        }
        Color-Write ("{0}" -f $m.notes_ar) Yellow
        Update-Stats -Progress $Progress -Mode 'nameit' -Family $m.family -IsCorrect:$ok -MoleculeId $m.id
    }
}

function Mode-PropertiesDuel {
    param([array]$Dataset, [hashtable]$Progress)
    Color-Write "`n=== وضع مقارنة الخواص: Properties Duel ===" Cyan
    $metrics = @('water_solubility', 'bp_relative', 'polarity')
    $metricAr = @{ water_solubility = 'الذوبانية في الماء'; bp_relative = 'درجة الغليان النسبية'; polarity = 'القطبية' }
    $rank = @{ low = 1; medium = 2; high = 3 }

    $count = Get-QuestionCount $Progress
    for ($i = 1; $i -le $count; $i++) {
        $pair = Pick-RandomDistinct -Items $Dataset -Count 2
        $a = $pair[0]; $b = $pair[1]
        $metric = $metrics | Get-Random

        Color-Write ("`nسؤال {0}/{1} - أيهما أعلى في {2}؟" -f $i, $count, $metricAr[$metric]) White
        Color-Write ("A) {0} ({1})" -f $a.display_formula, (Get-FamilyLabelAr $a.family)) DarkGray
        Color-Write ("B) {0} ({1})" -f $b.display_formula, (Get-FamilyLabelAr $b.family)) DarkGray
        $ans = Read-Choice -Prompt 'اختر A أو B' -ValidChoices @('A', 'B', 'a', 'b')

        $av = $rank[[string]$a.property_tags.$metric]
        $bv = $rank[[string]$b.property_tags.$metric]
        $correct = if ($av -ge $bv) { 'A' } else { 'B' }
        $user = $ans.ToUpper()
        $ok = $user -eq $correct

        if ($ok) { Color-Write '✅ صحيح.' Green }
        else { Color-Write ("❌ الإجابة الصحيحة: $correct") Red }

        $winner = if ($correct -eq 'A') { $a } else { $b }
        Color-Write (Compute-Reasoning -Mol $winner -Property $metric) Yellow
        Update-Stats -Progress $Progress -Mode 'duel' -Family $winner.family -IsCorrect:$ok -MoleculeId $winner.id
    }
}

function Mode-BuildExplain {
    param([array]$Dataset)
    Color-Write "`n=== وضع البناء النصي: Build & Explain ===" Cyan
    $inputFormula = Read-NonEmpty -Prompt 'أدخل صيغة مكثفة (مثال: CH3CH2OH)'
    $normalized = Normalize-Input $inputFormula
    $family = Classify-Formula -Formula $normalized

    $exact = $Dataset | Where-Object { (Normalize-Input $_.display_formula) -eq $normalized } | Select-Object -First 1
    $chain = ([regex]::Matches($normalized, 'C')).Count
    if ($chain -lt 1) { $chain = 1 }
    $props = if ($exact) { $exact.property_tags } else { Estimate-Properties -Family $family -Carbons $chain }

    $familyAr = Get-FamilyLabelAr $family
    $shown = Get-HighlightFormula -Formula $normalized -Family $family

    Color-Write "`n----- Explain Card -----" Cyan
    Color-Write ("1) من أنا؟ {0} | الصيغة: {1}" -f $familyAr, $shown) White
    if ($exact) { Color-Write ("2) اسمي: {0} ({1})" -f $exact.name_ar, $exact.name_en) White }
    else { Color-Write '2) اسمي: غير موجود في قاعدة البيانات' White }

    Color-Write "3) خواصي المتوقعة:" White
    Color-Write ("- القطبية: {0}" -f $props.polarity) DarkGray
    Color-Write ("- روابط هيدروجينية: {0}" -f ($(if ($props.hbond) { 'نعم' } else { 'لا' }))) DarkGray
    Color-Write ("- الذوبانية في الماء: {0}" -f $props.water_solubility) DarkGray
    Color-Write ("- درجة الغليان النسبية: {0}" -f $props.bp_relative) DarkGray

    Color-Write '4) لماذا؟' White
    Color-Write ("- المجموعة الوظيفية الأساسية هنا: {0}." -f $familyAr) Yellow
    Color-Write ("- طول السلسلة الكربونية التقريبي: {0} ذرة كربون." -f $chain) Yellow
    Color-Write ("- وجود/غياب الروابط الهيدروجينية يؤثر في الذوبانية والغليان.") Yellow
    Color-Write ("- هذا توقع مدرسي مبسط متوافق مع الفصل الدراسي.") Yellow
}

function Mode-ProgressDashboard {
    param([hashtable]$Progress)
    Color-Write "`n=== تقدمي وأخطائي المتكررة ===" Cyan
    $total = [int]$Progress.total_answered
    $correct = [int]$Progress.correct_answers
    $acc = if ($total -gt 0) { [math]::Round(($correct / $total) * 100, 1) } else { 0 }

    Color-Write ("الإجمالي: {0} | الصحيح: {1} | الدقة: {2}%" -f $total, $correct, $acc) White
    Color-Write ("سلسلة الأيام: {0} يوم" -f $Progress.streak_days) White

    Color-Write "`nدقة حسب الوضع:" DarkCyan
    foreach ($k in $Progress.mode_stats.Keys) {
        $m = $Progress.mode_stats[$k]
        $mAcc = if ($m.total -gt 0) { [math]::Round(($m.correct / $m.total) * 100, 1) } else { 0 }
        Color-Write ("- {0}: {1}/{2} ({3}%)" -f $k, $m.correct, $m.total, $mAcc) DarkGray
    }

    Color-Write "`nدقة حسب العائلة:" DarkCyan
    foreach ($k in $Progress.family_stats.Keys) {
        $f = $Progress.family_stats[$k]
        $fAcc = if ($f.total -gt 0) { [math]::Round(($f.correct / $f.total) * 100, 1) } else { 0 }
        Color-Write ("- {0}: {1}/{2} ({3}%)" -f (Get-FamilyLabelAr $k), $f.correct, $f.total, $fAcc) DarkGray
    }

    Color-Write "`nأكثر 10 أخطاء تكرارًا:" DarkCyan
    $top = $Progress.mistakes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10
    if (-not $top) { Color-Write '- لا توجد أخطاء مسجلة بعد.' DarkGray }
    foreach ($item in $top) {
        Color-Write ("- {0}: {1} مرة" -f $item.Key, $item.Value) DarkGray
    }
}

function Mode-Settings {
    param([hashtable]$Progress)
    Color-Write "`n=== الإعدادات ===" Cyan
    Color-Write ("1) مستوى الصعوبة الحالي: {0}" -f $Progress.settings.difficulty) White
    Color-Write ("2) عدد الأسئلة لكل جلسة: {0}" -f $Progress.settings.question_count) White
    Color-Write ("3) مؤقت (ثانية لكل سؤال، 0 = بدون): {0}" -f $Progress.settings.timer_seconds) White

    $c = Read-Choice -Prompt 'اختر (1/2/3/0 للعودة)' -ValidChoices @('1', '2', '3', '0')
    switch ($c) {
        '1' {
            $d = Read-Choice -Prompt 'اختر الصعوبة: 1) سهل 2) متوسط 3) صعب' -ValidChoices @('1', '2', '3')
            if ($d -eq '1') { $Progress.settings.difficulty = 'سهل'; $Progress.settings.timer_seconds = 0 }
            elseif ($d -eq '2') { $Progress.settings.difficulty = 'متوسط'; $Progress.settings.timer_seconds = 0 }
            else { $Progress.settings.difficulty = 'صعب'; if ([int]$Progress.settings.timer_seconds -eq 0) { $Progress.settings.timer_seconds = 20 } }
            Color-Write 'تم تحديث الصعوبة.' Green
        }
        '2' {
            $q = Read-NonEmpty -Prompt 'أدخل عدد الأسئلة (1-50)'
            if ($q -match '^\d+$' -and [int]$q -ge 1 -and [int]$q -le 50) {
                $Progress.settings.question_count = [int]$q
                Color-Write 'تم حفظ العدد.' Green
            } else {
                Color-Write 'قيمة غير صالحة. يجب أن تكون بين 1 و50.' Yellow
            }
        }
        '3' {
            $t = Read-NonEmpty -Prompt 'أدخل المؤقت بالثواني (0-120)'
            if ($t -match '^\d+$' -and [int]$t -ge 0 -and [int]$t -le 120) {
                $Progress.settings.timer_seconds = [int]$t
                Color-Write 'تم حفظ المؤقت.' Green
            } else {
                Color-Write 'قيمة غير صالحة.' Yellow
            }
        }
        default {}
    }
}

function Show-MainMenu {
    Color-Write "`n================ OrganicBuilderCLI ================" Magenta
    Color-Write '1) وضع التدريب السريع: اكتشاف المجموعة الوظيفية' Cyan
    Color-Write '2) وضع التسمية المبسطة: Name-It' Cyan
    Color-Write '3) وضع مقارنة الخواص: Properties Duel' Cyan
    Color-Write '4) وضع البناء النصي: Build & Explain' Cyan
    Color-Write '5) تقدمي وأخطائي المتكررة' Cyan
    Color-Write '6) إعدادات' Cyan
    Color-Write '0) خروج' Cyan
}

try {
    $paths = Initialize-App
    $dataset = Load-Dataset -DatasetPath $paths.dataset
    $progress = Load-Progress -ProgressPath $paths.progress
    Update-Streak -Progress $progress

    while ($true) {
        Show-MainMenu
        $choice = Read-Choice -Prompt 'اختر من القائمة' -ValidChoices @('1', '2', '3', '4', '5', '6', '0')
        switch ($choice) {
            '1' { Mode-Identify -Dataset $dataset -Progress $progress }
            '2' { Mode-NameIt -Dataset $dataset -Progress $progress }
            '3' { Mode-PropertiesDuel -Dataset $dataset -Progress $progress }
            '4' { Mode-BuildExplain -Dataset $dataset }
            '5' { Mode-ProgressDashboard -Progress $progress }
            '6' { Mode-Settings -Progress $progress }
            '0' {
                Save-Progress -ProgressPath $paths.progress -Progress $progress
                Color-Write 'تم حفظ التقدم. إلى اللقاء!' Green
                break
            }
        }
        Save-Progress -ProgressPath $paths.progress -Progress $progress
    }
} catch {
    Color-Write ("حدث خطأ غير متوقع: $($_.Exception.Message)") Red
    exit 1
}
