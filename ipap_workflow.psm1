# IPAP 工作流 PowerShell 模块

# 模块初始化
function Initialize-IpapModule
{
    <#
    .SYNOPSIS
        初始化 IPAP 工作流 PowerShell 模块。

    .DESCRIPTION
        初始化 IPAP 工作流模块，确保模块能够正常运行。
        加上 CmdletBinding() 后，函数会自动获得以下功能：
        - 通用参数支持：-Verbose, -Debug, -ErrorAction 等
        - 参数验证特性
        - 自动变量 $PSCmdlet
        - Write-Verbose / Write-Debug 支持
        - 参数集支持

    .EXAMPLE
        Initialize-IpapModule

    .EXAMPLE
        # 通过管道调用
        $true | Initialize-IpapModule

    .INPUTS
        无

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()
    
    try
    {
        # 模块初始化成功
        Write-Verbose '模块初始化成功'
        return $true
    }
    catch
    {
        Write-Error "模块初始化失败： $($PSItem.Exception.Message)"
        return $false
    }
}

function Get-IpapConfig
{
    <#
    .SYNOPSIS
        加载并验证 ipap_workflow 的 TOML 配置文件。

    .DESCRIPTION
        1. 动态探测 bin/ 目录下的二进制解析工具。
        2. 若配置文件缺失，生成示例文件并返回默认值。
        3. 解析 TOML 并进行严格的数据类型、数值范围及路径真实性校验。

    .EXAMPLE
        Get-IpapConfig

    .EXAMPLE
        # 通过管道调用
        $true | Get-IpapConfig

    .INPUTS
        无

    .OUTPUTS
        System.Management.Automation.PSCustomObject

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [System.String]$ConfigPath
    )

    # --- 环境初始化 ---
    # 强制设置 UTF8 编码，防止外部进程处理中文路径时乱码
    $OutputEncoding = [System.Text.Encoding]::UTF8
    $rootPath = $PSScriptRoot
    $binPath = Join-Path -Path $rootPath -ChildPath 'bin'
    $parserExe = Join-Path -Path $binPath -ChildPath 'tomljson.exe'
    if (-not $ConfigPath)
    {
        $ConfigPath = Join-Path -Path $rootPath -ChildPath 'config.toml'
    }
    $examplePath = Join-Path -Path $rootPath -ChildPath 'config.toml.example'
    $parserDownloadUrl = 'https://github.com/pelletier/go-toml/releases'

    # --- 内部硬编码默认配置 ---
    $defaultConfig = [PSCustomObject]@{
        paths        = @{
            base_project_dir   = 'D:/documents/translation/01_Projects_Active'
            project_dir_prefix = ''
            archive_dir        = 'D:/documents/translation/02_Archive'
        }
        logging      = @{
            level    = 'INFO'
            colorize = $true
        }
        app_settings = @{
            max_workers         = 8
            upscale_timeout_sec = 3600
            model_select        = 'models-se'
        }
        upscale      = @{
            upscale_ratio = 2
            noise_level   = 0
        }
        webp         = @{
            enabled  = $true
            lossless = $true
            quality  = 100
        }
    }

    # --- 1. 检查解析工具是否存在 ---
    if (-not (Test-Path -Path $parserExe))
    {
        throw @"
[环境错误] 未找到解析工具: $parserExe
请下载解析器并放入 bin 目录，重命名为 toml-parser.exe。
下载地址: $parserDownloadUrl
"@
    }

    # --- 2. 配置文件存在性检查 ---
    if (-not (Test-Path -Path $ConfigPath))
    {
        Write-Warning "未找到配置文件: $ConfigPath，将使用硬编码的默认配置。"
        New-ExampleConfig -OutputPath $examplePath
        return $defaultConfig
    }

    # --- 3. 调用二进制工具解析 TOML ---
    try
    {
        # 执行转换：TOML -> JSON
        $jsonContent = & $parserExe $ConfigPath 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            throw "TOML 语法解析失败: $jsonContent"
        }
        
        $config = $jsonContent | ConvertFrom-Json
    }
    catch
    {
        throw "[文件错误] 无法解析 config.toml。请确保文件格式符合 TOML 标准。详情: $($PSItem.Exception.Message)"
    }

    # --- 4. 严格校验逻辑 ---
    Test-IpapConfig -Config $config

    Write-Verbose '配置文件加载并校验成功。'
    return $config
}

function Test-IpapConfig
{
    <#
    .SYNOPSIS
        验证 IPAP 工作流的配置对象。

    .DESCRIPTION
        对配置对象进行严格的验证，包括：
        1. 路径校验：确保路径字段非空且真实存在
        2. 数值合法性校验：确保 upscale_ratio 为有效值
        3. 数值范围校验：确保 noise_level 在有效范围内

    .PARAMETER Config
        要验证的配置对象。

    .EXAMPLE
        Test-IpapConfig -Config $config

    .EXAMPLE
        # 通过管道调用
        $config | Test-IpapConfig

    .INPUTS
        System.Management.Automation.PSCustomObject

    .OUTPUTS
        无

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Config
    )

    # A. 路径校验 (必须非空且真实存在)
    $pathFields = @('base_project_dir', 'archive_dir')
    foreach ($field in $pathFields)
    {
        $val = $Config.paths.$field
        if ([string]::IsNullOrWhiteSpace($val))
        {
            throw "[配置错误] paths.$field 不能为空字符串。`n修复建议: 请在 config.toml 中填写有效的目录路径。"
        }
        if (-not (Test-Path -Path $val))
        {
            throw "[路径不存在] 字段 paths.$field 的值 '$val' 在磁盘上未找到。`n修复建议: 请手动创建该目录或修正 config.toml 中的路径。"
        }
    }

    # B. 数值合法性校验 (upscale_ratio)
    $validRatios = 2, 3, 4
    if ($Config.upscale.upscale_ratio -notin $validRatios)
    {
        throw "[参数非法] upscale.upscale_ratio 的值为 '$($Config.upscale.upscale_ratio)'。`n修复建议: 该值必须是 [2, 3, 4] 之一，请检查并修改 config.toml。"
    }

    # C. 数值范围校验 (noise_level)
    if ($Config.upscale.noise_level -lt 0 -or $Config.upscale.noise_level -gt 3)
    {
        throw "[参数非法] upscale.noise_level 的值为 '$($Config.upscale.noise_level)'。`n修复建议: 降噪级别必须在 0 到 3 之间，请检查并修改 config.toml。"
    }
}

function New-ExampleConfig
{
    <#
    .SYNOPSIS
        生成 IPAP 工作流的配置文件模板。

    .DESCRIPTION
        生成一个示例配置文件模板，包含默认的配置值和注释说明。

    .PARAMETER OutputPath
        输出文件路径。

    .EXAMPLE
        New-ExampleConfig -OutputPath '.\config.toml.example'

    .EXAMPLE
        # 通过管道调用
        '.\config.toml.example' | New-ExampleConfig

    .INPUTS
        System.String

    .OUTPUTS
        无

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [System.String]$OutputPath
    )
    $exampleContent = @'
# config.toml.example - 自动生成的模板文件

[paths]
base_project_dir = "D:/documents/translation/01_Projects_Active"
archive_dir = "D:/documents/translation/02_Archive"

[app_settings]
max_workers = 8
model_select = "models-se"

[upscale]
upscale_ratio = 2  # 可选: 2, 3, 4
noise_level = 0    # 可选: 0, 1, 2, 3

[webp]
enabled = true
lossless = true
quality = 100
'@
    if (-not (Test-Path $OutputPath))
    {
        $exampleContent | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "已生成配置文件模板: $OutputPath" -ForegroundColor Gray
    }
}

# 扫描目录中的图像文件
function Get-IpapImageFiles
{
    <#
    .SYNOPSIS
        扫描目录中的图像文件。

    .DESCRIPTION
        递归扫描指定目录，找出所有支持的图像文件。

    .PARAMETER DirectoryPath
        要扫描的目录路径。

    .EXAMPLE
        Get-IpapImageFiles -DirectoryPath 'D:\path\to\images'

    .EXAMPLE
        # 通过管道调用
        'D:\path\to\images' | Get-IpapImageFiles

    .INPUTS
        System.String

    .OUTPUTS
        System.IO.FileInfo[]

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.String]$DirectoryPath
    )
    
    try
    {
        # 检查目录是否存在
        if (-not (Test-Path -Path $DirectoryPath -PathType Container))
        {
            throw "目录不存在： $DirectoryPath"
        }
        
        # 定义支持的图像扩展名
        $imageExtensions = @('.jpg', '.jpeg', '.png', '.bmp', '.gif', '.webp')
        
        # 搜索图像文件
        $imageFiles = Get-ChildItem -Path $DirectoryPath -Recurse -File | Where-Object {
            $imageExtensions -contains $PSItem.Extension.ToLower()
        }
        
        Write-Verbose "找到 $($imageFiles.Count) 图像"
        return $imageFiles
    }
    catch
    {
        Write-Error "扫描图像文件失败： $($PSItem.Exception.Message)"
        return @()
    }
}

# 分析图像文件属性
function Get-IpapImageInfo
{
    <#
    .SYNOPSIS
        分析图像文件属性。

    .DESCRIPTION
        分析图像文件的属性，包括数量、总大小和平均大小。

    .PARAMETER ImageFiles
        图像文件对象数组。

    .EXAMPLE
        Get-IpapImageInfo -ImageFiles $imageFiles

    .EXAMPLE
        # 通过管道调用
        $imageFiles | Get-IpapImageInfo

    .INPUTS
        System.IO.FileInfo[]

    .OUTPUTS
        System.Collections.Hashtable

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.IO.FileInfo[]]$ImageFiles
    )
    
    try
    {
        if ($ImageFiles.Count -eq 0)
        {
            return @{ Count = 0; TotalSize = 0; AvgSize = 0 }
        }
        
        # 计算总大小和平均大小
        $totalSize = $ImageFiles | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum
        $avgSize = $totalSize / $ImageFiles.Count
        
        return @{
            Count     = $ImageFiles.Count
            TotalSize = $totalSize
            AvgSize   = $avgSize
        }
    }
    catch
    {
        Write-Error "无法分析图像文件属性： $($PSItem.Exception.Message)"
        return @{ Count = 0; TotalSize = 0; AvgSize = 0 }
    }
}

# 创建项目目录结构
function New-IpapProjectStructure
{
    <#
    .SYNOPSIS
        创建项目目录结构。

    .DESCRIPTION
        创建项目目录结构，包括基础目录和所有必要的子目录。

    .PARAMETER BaseDirectory
        基础目录路径。

    .PARAMETER ProjectName
        项目名称。

    .EXAMPLE
        New-IpapProjectStructure -BaseDirectory 'D:\projects' -ProjectName '测试项目'

    .EXAMPLE
        # 通过管道调用
        'D:\projects' | New-IpapProjectStructure -ProjectName '测试项目'

    .INPUTS
        System.String

    .OUTPUTS
        System.String

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.String]$BaseDirectory,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$ProjectName
    )
    
    try
    {
        # 检查基本目录是否存在
        if (-not (Test-Path -Path $BaseDirectory -PathType Container))
        {
            New-Item -Path $BaseDirectory -ItemType Directory -Force | Out-Null
        }
        
        # 创建项目目录
        $datePrefix = Get-Date -Format 'yyyy-dd-mm'
        $projectDirectory = Join-Path -Path $BaseDirectory -ChildPath "$datePrefix`_$ProjectName"
        
        # 创建子目录结构
        $subDirectories = @(
            '02_Preprocessing/raw_source',
            '02_Preprocessing/original_non_text_raw',
            '02_Preprocessing/inpainted',
            '02_Preprocessing/mask',
            '03_Translation',
            '04_Typesetting/workfiles',
            '04_Typesetting/final_pages'
        )
        
        foreach ($subDir in $subDirectories)
        {
            $fullPath = Join-Path -Path $projectDirectory -ChildPath $subDir
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
        }
        
        Write-Verbose "项目目录结构创建成功： $projectDirectory"
        return $projectDirectory
    }
    catch
    {
        Write-Error "无法创建项目目录结构： $($PSItem.Exception.Message)"
        return $null
    }
}

# 复制图像并分析
function Copy-IpapImagesAndAnalyze
{
    <#
    .SYNOPSIS
        复制图像并分析。

    .DESCRIPTION
        复制图像文件到项目目录，并分析图像的数量、总大小和最大大小。

    .PARAMETER SourcePath
        源图像路径，可以是文件或目录。

    .PARAMETER ProjectDirectory
        项目目录路径。

    .EXAMPLE
        Copy-IpapImagesAndAnalyze -SourcePath 'D:\path\to\images' -ProjectDirectory 'D:\projects\test'

    .EXAMPLE
        # 通过管道调用
        'D:\path\to\images' | Copy-IpapImagesAndAnalyze -ProjectDirectory 'D:\projects\test'

    .INPUTS
        System.String

    .OUTPUTS
        System.Object[]

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.String]$SourcePath,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$ProjectDirectory
    )
    
    try
    {
        # 检查源路径是否存在
        if (-not (Test-Path -Path $SourcePath))
        {
            throw "源路径不存在： $SourcePath"
        }
        
        # 确定源路径类型
        $sourceIsFile = Test-Path -Path $SourcePath -PathType Leaf
        $sourceIsDir = Test-Path -Path $SourcePath -PathType Container
        
        # 复制图像文件
        $sourceDirectory = $ProjectDirectory + '/01_Projects_Active'
        if (-not (Test-Path -Path $sourceDirectory -PathType Container))
        {
            New-Item -Path $sourceDirectory -ItemType Directory -Force | Out-Null
        }
        
        if ($sourceIsFile)
        {
            # 复制单个文件
            $fileName = Split-Path -Path $SourcePath -Leaf
            $destinationPath = Join-Path -Path $sourceDirectory -ChildPath $fileName
            Copy-Item -Path $SourcePath -Destination $destinationPath -Force
            
            # 获取图像文件
            $imageFiles = @(Get-Item -Path $destinationPath)
        }
        elseif ($sourceIsDir)
        {
            # 复制目录中的所有文件
            Copy-Item -Path "$SourcePath\*" -Destination $sourceDirectory -Recurse -Force
            
            # 获取图像文件
            $imageFiles = Get-IpapImageFiles -DirectoryPath $sourceDirectory
        }
        else
        {
            throw "源路径既不是文件也不是目录： $SourcePath"
        }
        
        # 分析图像
        $imageCount = $imageFiles.Count
        $totalSize = ($imageFiles | Measure-Object -Property Length -Sum).Sum
        $maxSize = ($imageFiles | Measure-Object -Property Length -Maximum).Maximum
        
        Write-Verbose "复制和分析完成，已找到 $imageCount 图像"
        return $imageFiles, $imageCount, $totalSize, $maxSize
    }
    catch
    {
        Write-Error "无法复制图像并进行分析： $($PSItem.Exception.Message)"
        return @(), 0, 0, 0
    }
}

# 执行图像放大
function Invoke-IpapUpscaling
{
    <#
    .SYNOPSIS
        执行图像放大。

    .DESCRIPTION
        使用 RealCugan 工具执行图像放大操作。

    .PARAMETER ImageFile
        要放大的图像文件对象。

    .PARAMETER OutputDirectory
        输出目录路径。

    .PARAMETER UpscaleRatio
        放大倍数。

    .PARAMETER ModelSelect
        模型选择。

    .PARAMETER RealCuganPath
        RealCugan 可执行文件路径。

    .EXAMPLE
        Invoke-IpapUpscaling -ImageFile $imageFile -OutputDirectory 'D:\output' -UpscaleRatio 2 -ModelSelect 'models-se' -RealCuganPath 'D:\tools\realcugan.exe'

    .EXAMPLE
        # 通过管道调用
        $imageFile | Invoke-IpapUpscaling -OutputDirectory 'D:\output' -UpscaleRatio 2 -ModelSelect 'models-se' -RealCuganPath 'D:\tools\realcugan.exe'

    .INPUTS
        System.IO.FileInfo

    .OUTPUTS
        System.String

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.IO.FileInfo]$ImageFile,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$OutputDirectory,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [System.Int32]$UpscaleRatio,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [System.String]$ModelSelect,
        
        [Parameter(Mandatory = $true, Position = 4)]
        [System.String]$RealCuganPath
    )
    
    try
    {
        # 检查 RealCugan 可执行文件是否存在
        if (-not (Test-Path -Path $RealCuganPath -PathType Leaf))
        {
            throw "RealCugan 可执行文件不存在： $RealCuganPath"
        }
        
        # 确保输出目录存在
        if (-not (Test-Path -Path $OutputDirectory -PathType Container))
        {
            New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        }
        
        # 构建输出文件路径
        $outputFileName = $ImageFile.Name
        $outputPath = Join-Path -Path $OutputDirectory -ChildPath $outputFileName
        
        # 构建命令参数
        $outputFormat = 'webp' # 输出格式默认为webp
        $arguments = @(
            '-i', "$($ImageFile.FullName)", # 输入文件路径
            '-o', "$outputPath",  # 输出文件路径
            '-s', "$UpscaleRatio", # 放大比例
            '-m', "$ModelSelect" # 模型选择
            '-f', $outputFormat # 输出格式
        )
        
        Write-Verbose "正在执行放大： $($ImageFile.Name) -> $outputFileName"
        
        # 执行命令
        $process = Start-Process -FilePath $RealCuganPath -ArgumentList $arguments -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -eq 0)
        {
            Write-Verbose "放大成功： $outputFileName"
            return $outputPath
        }
        else
        {
            throw "放大失败，退出代码： $($process.ExitCode)"
        }
    }
    catch
    {
        Write-Error "执行放大失败： $($PSItem.Exception.Message)"
        return $null
    }
}


# 归档原始文件
function Move-IpapOriginalSource
{
    <#
    .SYNOPSIS
        归档原始文件。

    .DESCRIPTION
        将原始文件归档到指定的目录。

    .PARAMETER SourceFile
        源文件对象。

    .PARAMETER ArchiveDirectory
        归档目录路径。

    .EXAMPLE
        Move-IpapOriginalSource -SourceFile $sourceFile -ArchiveDirectory 'D:\archive'

    .EXAMPLE
        # 通过管道调用
        $sourceFile | Move-IpapOriginalSource -ArchiveDirectory 'D:\archive'

    .INPUTS
        System.IO.FileInfo

    .OUTPUTS
        System.String

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.IO.FileInfo]$SourceFile,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$ArchiveDirectory
    )
    
    try
    {
        # 确保归档目录存在
        if (-not (Test-Path -Path $ArchiveDirectory -PathType Container))
        {
            New-Item -Path $ArchiveDirectory -ItemType Directory -Force | Out-Null
        }
        
        # 构建归档文件路径
        $archiveFileName = $SourceFile.Name
        $archivePath = Join-Path -Path $ArchiveDirectory -ChildPath $archiveFileName
        
        # 处理文件名冲突
        $counter = 1
        while (Test-Path -Path $archivePath -PathType Leaf)
        {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($SourceFile.Name)
            $extension = $SourceFile.Extension
            $archiveFileName = "$baseName ($counter)$extension"
            $archivePath = Join-Path -Path $ArchiveDirectory -ChildPath $archiveFileName
            $counter++
        }
        
        if ($PSCmdlet.ShouldProcess($SourceFile.FullName, "移动到 $archivePath"))
        {
            # 移动文件
            Move-Item -LiteralPath $SourceFile.FullName -Destination $archivePath -Force
            Write-Verbose "文件已成功归档： $($SourceFile.Name) -> $archiveFileName"
            return $archivePath
        }
        else
        {
            Write-Verbose "正在模拟文件归档： $($SourceFile.Name) -> $archiveFileName"
            return $archivePath
        }
    }
    catch
    {
        Write-Error "无法归档文件： $($PSItem.Exception.Message)"
        return $null
    }
}

# 图像的并行处理
function Invoke-IpapParallelProcessing
{
    <#
    .SYNOPSIS
        并行处理图像。

    .DESCRIPTION
        并行处理多张图像，执行放大和 WebP 转换操作。

    .PARAMETER ImageFiles
        图像文件对象数组。

    .PARAMETER OutputDirectory
        输出目录路径。

    .PARAMETER UpscaleRatio
        放大倍数。

    .PARAMETER ModelSelect
        模型选择。

    .PARAMETER MaxConcurrent
        最大并发数。

    .EXAMPLE
        Invoke-IpapParallelProcessing -ImageFiles $imageFiles -OutputDirectory 'D:\output' -UpscaleRatio 2 -ModelSelect 'models-se' -MaxConcurrent 4

    .EXAMPLE
        # 通过管道调用
        $imageFiles | Invoke-IpapParallelProcessing -OutputDirectory 'D:\output' -UpscaleRatio 2 -ModelSelect 'models-se' -MaxConcurrent 4

    .INPUTS
        System.IO.FileInfo[]

    .OUTPUTS
        System.Object[]

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.IO.FileInfo[]]$ImageFiles,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$OutputDirectory,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [System.Int32]$UpscaleRatio,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [System.String]$ModelSelect,
        
        [Parameter(Mandatory = $true, Position = 4)]
        [System.Int32]$MaxConcurrent
    )
    
    try
    {
        # 确保输出目录存在
        if (-not (Test-Path -Path $OutputDirectory -PathType Container))
        {
            New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
        }
        
        # 并行处理图像
        $results = $ImageFiles | ForEach-Object -Parallel {
            $imageFile = $PSItem
            $outputDir = $using:OutputDirectory
            $upscaleRatio = $using:UpscaleRatio
            $modelSelect = $using:ModelSelect
            $realCuganPath = "$using:PSScriptRoot\realcugan ncnn vulkan 20220728 windows\realcugan ncnn vulkan.exe"
            
            try
            {
                # 执行放大
                $upscaledPath = Invoke-IpapUpscaling -ImageFile $imageFile -OutputDirectory $outputDir -UpscaleRatio $upscaleRatio -ModelSelect $modelSelect -RealCuganPath $realCuganPath
                
                if ($upscaledPath)
                {
                    # 转换为 WebP
                    $webpPath = Convert-IpapImageToWebP -ImagePath $upscaledPath -OutputDirectory $outputDir
                    return @{ Success = $true; Original = $imageFile.FullName; Upscaled = $upscaledPath; WebP = $webpPath }
                }
                else
                {
                    return @{ Success = $false; Original = $imageFile.FullName; Error = '放大失败' }
                }
            }
            catch
            {
                return @{ Success = $false; Original = $imageFile.FullName; Error = $PSItem.Exception.Message }
            }
        } -ThrottleLimit $MaxConcurrent
        
        return $results
    }
    catch
    {
        Write-Error "无法并行处理图像： $($PSItem.Exception.Message)"
        return @()
    }
}

# 处理图像
function Process-IpapImages
{
    <#
    .SYNOPSIS
        处理图像。

    .DESCRIPTION
        处理图像文件，执行放大和 WebP 转换操作。

    .PARAMETER ImageFiles
        图像文件对象数组。

    .PARAMETER ProjectDirectory
        项目目录路径。

    .PARAMETER Settings
        配置设置哈希表。

    .PARAMETER AverageSizeKB
        图像平均大小（KB）。

    .EXAMPLE
        Process-IpapImages -ImageFiles $imageFiles -ProjectDirectory 'D:\projects\test' -Settings $config -AverageSizeKB 500

    .EXAMPLE
        # 通过管道调用
        $imageFiles | Process-IpapImages -ProjectDirectory 'D:\projects\test' -Settings $config -AverageSizeKB 500

    .INPUTS
        System.IO.FileInfo[]

    .OUTPUTS
        System.Object[]

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.IO.FileInfo[]]$ImageFiles,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$ProjectDirectory,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [System.Collections.Hashtable]$Settings,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [System.Double]$AverageSizeKB
    )
    
    try
    {
        # 读取配置
        $upscaleRatio = $Settings.upscale.upscale_ratio
        $modelSelect = $Settings.app_settings.model_select
        $maxWorkers = $Settings.app_settings.max_workers
        $webpEnabled = $Settings.webp.enabled
        
        # 准备输出目录
        $upscaledDir = Join-Path -Path $ProjectDirectory -ChildPath '02 预处理\放大'
        $webpDir = Join-Path -Path $ProjectDirectory -ChildPath '02 预处理\webp'
        
        # 并行处理图像
        Write-Host "开始并行处理 $($ImageFiles.Count) 图片..." -ForegroundColor Green
        $results = Invoke-IpapParallelProcessing -ImageFiles $ImageFiles -OutputDirectory $upscaledDir -UpscaleRatio $upscaleRatio -ModelSelect $modelSelect -MaxConcurrent $maxWorkers
        
        # 计算结果
        $successCount = $results | Where-Object { $PSItem.Success } | Measure-Object | Select-Object -ExpandProperty Count
        $failedCount = $results | Where-Object { -not $PSItem.Success } | Measure-Object | Select-Object -ExpandProperty Count
        
        Write-Host "处理完成： $successCount 成功 $failedCount 失败" -ForegroundColor Green
        
        # 显示失败的文件
        if ($failedCount -gt 0)
        {
            Write-Host '失败的文件：' -ForegroundColor Red
            $results | Where-Object { -not $PSItem.Success } | ForEach-Object {
                Write-Host "- $($PSItem.Original): $($PSItem.Error)" -ForegroundColor Red
            }
        }
        
        return $results
    }
    catch
    {
        Write-Error "处理图片失败： $($PSItem.Exception.Message)"
        return @()
    }
}

# 创建项目文件
function New-IpapProjectFiles
{
    <#
    .SYNOPSIS
        创建项目文件。

    .DESCRIPTION
        创建项目相关文件，包括 README.md、项目简介和词汇表。

    .PARAMETER ProjectDirectory
        项目目录路径。

    .PARAMETER BriefText
        项目简介文本。

    .PARAMETER ProjectName
        项目名称。

    .PARAMETER ImageCount
        图片数量。

    .PARAMETER AverageSizeKB
        图片平均大小（KB）。

    .EXAMPLE
        New-IpapProjectFiles -ProjectDirectory 'D:\projects\test' -BriefText '测试项目' -ProjectName '测试' -ImageCount 10 -AverageSizeKB 500

    .EXAMPLE
        # 通过管道调用
        'D:\projects\test' | New-IpapProjectFiles -BriefText '测试项目' -ProjectName '测试' -ImageCount 10 -AverageSizeKB 500

    .INPUTS
        System.String

    .OUTPUTS
        System.Boolean

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.String]$ProjectDirectory,
        
        [Parameter(Mandatory = $true, Position = 1)]
        [System.String]$BriefText,
        
        [Parameter(Mandatory = $true, Position = 2)]
        [System.String]$ProjectName,
        
        [Parameter(Mandatory = $true, Position = 3)]
        [System.Int32]$ImageCount,
        
        [Parameter(Mandatory = $true, Position = 4)]
        [System.Double]$AverageSizeKB
    )
    
    try
    {
        # 创建 README.md
        $readmePath = Join-Path -Path $ProjectDirectory -ChildPath '自述文件.md'
        $readmeContent = @(
            "# $ProjectName",
            '',
            '## 项目信息',
            "- 项目名称： $ProjectName",
            "- 图片数量： $ImageCount",
            "- 平均尺寸： $([math]::Round($AverageSizeKB, 2)) 千字节",
            "- 创建日期： $(Get-Date -Format '年年年年月月日')",
            '',
            '## 项目简介',
            $BriefText
        )
        $readmeContent | Out-File -FilePath $readmePath -Encoding UTF8
        
        # 创建项目简报文件
        $briefPath = Join-Path -Path $ProjectDirectory -ChildPath '03 翻译\项目简介.md'
        $briefContent = @(
            '# 项目简介',
            '',
            $BriefText,
            '',
            '## 翻译说明',
            '- 保持原有风格',
            '- 注意文化差异',
            '- 确保翻译准确'
        )
        $briefContent | Out-File -FilePath $briefPath -Encoding UTF8
        
        # 创建术语表文件
        $glossaryPath = Join-Path -Path $ProjectDirectory -ChildPath '03 翻译\词汇表.json'
        $glossaryContent = @{
            '条款' = @()
        } | ConvertTo-Json -Depth 3
        $glossaryContent | Out-File -FilePath $glossaryPath -Encoding UTF8
        
        Write-Verbose '项目文件创建成功'
        return $true
    }
    catch
    {
        Write-Error "创建项目文件失败： $($PSItem.Exception.Message)"
        return $false
    }
}

# 建立项目
function Set-IpapProject
{
    <#
    .SYNOPSIS
        建立项目。

    .DESCRIPTION
        设置项目，包括获取用户输入和创建项目目录结构。

    .PARAMETER Settings
        配置设置哈希表。

    .EXAMPLE
        Set-IpapProject -Settings $config

    .EXAMPLE
        # 通过管道调用
        $config | Set-IpapProject

    .INPUTS
        System.Collections.Hashtable

    .OUTPUTS
        System.Object[]

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.Collections.Hashtable]$Settings
    )
    
    try
    {
        # 读取配置
        $baseProjectDir = $Settings.paths.base_project_dir
        
        # 提示用户输入
        $srcPath = Read-Host '请输入源图像路径（文件或文件夹）'
        $briefText = Read-Host '请输入项目简报'
        $projectName = Read-Host '请输入项目名称'
        
        # 创建项目目录结构
        $projDir = New-IpapProjectStructure -BaseDirectory $baseProjectDir -ProjectName $projectName
        
        return $srcPath, $briefText, $projectName, $projDir
    }
    catch
    {
        Write-Error "设置项目失败： $($PSItem.Exception.Message)"
        return $null, $null, $null, $null
    }
}

# 主要工作流程功能
function Invoke-IpapWorkflow
{
    <#
    .SYNOPSIS
        执行 IPAP 工作流。

    .DESCRIPTION
        执行完整的工作流，包括图像高清化、WebP 转换和文件归档。

    .PARAMETER SourceDirectory
        源图像目录路径。

    .PARAMETER ConfigPath
        配置文件路径。

    .PARAMETER UpscaleRatio
        放大倍数。

    .PARAMETER ModelSelect
        模型选择。

    .EXAMPLE
        Invoke-IpapWorkflow -SourceDirectory 'D:\path\to\images'

    .EXAMPLE
        # 通过管道调用
        'D:\path\to\images' | Invoke-IpapWorkflow

    .INPUTS
        System.String

    .OUTPUTS
        System.String

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = '中等')]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [System.String]$SourceDirectory,
        
        [Parameter(Mandatory = $false, Position = 1)]
        [System.String]$ConfigPath = "$PSScriptRoot\config.toml",
        
        [Parameter(Mandatory = $false, Position = 2)]
        [System.Int32]$UpscaleRatio,
        
        [Parameter(Mandatory = $false, Position = 3)]
        [System.String]$ModelSelect
    )
    
    try
    {
        # 初始化模块
        if (-not (Initialize-IpapModule))
        {
            throw '模块初始化失败'
        }
        
        # 加载配置
        $config = Get-IpapConfig -ConfigPath $ConfigPath
        if (-not $config)
        {
            throw '加载配置失败'
        }
        
        # 读取配置参数
        $baseProjectDir = $config.paths.base_project_dir
        $archiveDirectory = $config.paths.archive_dir
        $maxWorkers = $config.app_settings.max_workers
        
        # 读取放大配置
        if (-not $UpscaleRatio)
        {
            $UpscaleRatio = $config.upscale.upscale_ratio
        }
        if (-not $ModelSelect)
        {
            $ModelSelect = $config.app_settings.model_select
        }
        $noiseLevel = $config.upscale.noise_level
        
        # 读取 WebP 配置
        $webpEnabled = $config.webp.enabled
        $webpLossless = $config.webp.lossless
        $webpQuality = $config.webp.quality
        
        # 扫描图像文件
        $imageFiles = Get-IpapImageFiles -DirectoryPath $SourceDirectory
        if ($imageFiles.Count -eq 0)
        {
            throw '未找到图像文件'
        }
        
        # 分析图像
        $imageInfo = Get-IpapImageInfo -ImageFiles $imageFiles
        Write-Host "找到 $($imageInfo.Count) 图片，总大小： $([math]::Round($imageInfo.TotalSize / 1MB, 2)) Mb" -ForegroundColor Green
        
        # 创建项目目录
        $projectName = "项目$(Get-Date -Format '年 年 月 日 小时 分秒')"
        $projectDirectory = New-IpapProjectStructure -BaseDirectory $baseProjectDir -ProjectName $projectName
        
        # 复制图片
        $copiedFiles, $copyCount, $totalSize, $maxSize = Copy-IpapImagesAndAnalyze -SourcePath $SourceDirectory -ProjectDirectory $projectDirectory
        
        # 处理图像
        $averageSizeKB = $totalSize / 1024 / $copyCount
        Process-IpapImages -ImageFiles $copiedFiles -ProjectDirectory $projectDirectory -Settings $config -AverageSizeKB $averageSizeKB
        
        # 创建项目文件
        $briefText = '自动创建的项目'
        New-IpapProjectFiles -ProjectDirectory $projectDirectory -BriefText $briefText -ProjectName $projectName -ImageCount $copyCount -AverageSizeKB $averageSizeKB
        
        Write-Host "工作流执行成功，项目目录： $projectDirectory" -ForegroundColor Green
        return $projectDirectory
    }
    catch
    {
        Write-Error "执行工作流失败： $($PSItem.Exception.Message)"
        return $null
    }
}

# 完整工作流功能
function Invoke-IpapCompleteWorkflow
{
    <#
    .SYNOPSIS
        执行完整的 IPAP 工作流。

    .DESCRIPTION
        执行完整的工作流，包括项目设置、图片处理、文档创建等。

    .PARAMETER ConfigPath
        配置文件路径。

    .EXAMPLE
        Invoke-IpapCompleteWorkflow

    .EXAMPLE
        # 通过管道调用
        'D:\path\to\config.toml' | Invoke-IpapCompleteWorkflow

    .INPUTS
        System.String

    .OUTPUTS
        System.String

    .NOTES
        Author:  lucas_gold
        Website: `https://github.com/1274248407`
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = '中等')]
    [OutputType([System.String])]
    param (
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true)]
        [System.String]$ConfigPath = "$PSScriptRoot\config.toml"
    )
    
    try
    {
        # 初始化模块
        if (-not (Initialize-IpapModule))
        {
            throw '模块初始化失败'
        }
        
        # 加载配置
        $config = Get-IpapConfig -ConfigPath $ConfigPath
        if (-not $config)
        {
            throw '加载配置失败'
        }
        
        # 建立项目
        $srcPath, $briefText, $projectName, $projDir = Set-IpapProject -Settings $config
        if (-not $srcPath -or -not $projDir)
        {
            Write-Host '项目设置失败，进程已结束。' -ForegroundColor Red
            return
        }
        
        # 复制并分析图像
        $imageFiles, $imageCount, $totalSize, $maxImageSize = Copy-IpapImagesAndAnalyze -SourcePath $srcPath -ProjectDirectory $projDir
        
        # 计算平均大小
        $avgKb = if ($imageCount -gt 0) { $totalSize / 1024 / $imageCount } else { 0 }
        
        if ($imageCount -eq 0)
        {
            Write-Warning '⚠️ 警告：未找到图像文件，进程已结束。'
            return
        }
        
        Write-Host "检测到$imageCount 图像，平均 $([math]::Round($avgKb, 2)) 千字节" -ForegroundColor Green
        Write-Host "最大图片尺寸： $([math]::Round($maxImageSize / 1024, 2)) 千字节" -ForegroundColor Green
        
        # 处理图像
        Process-IpapImages -ImageFiles $imageFiles -ProjectDirectory $projDir -Settings $config -AverageSizeKB $avgKb
        
        # 创建项目文件
        New-IpapProjectFiles -ProjectDirectory $projDir -BriefText $briefText -ProjectName $projectName -ImageCount $imageCount -AverageSizeKB $avgKb
        
        Write-Host '🎉 完整工作流程已成功执行！' -ForegroundColor Green
        Write-Host "项目目录： $projDir" -ForegroundColor Cyan
        
        return $projDir
    }
    catch
    {
        Write-Error "无法执行完整工作流程： $($PSItem.Exception.Message)"
        return $null
    }
}

# 导出功能
Export-ModuleMember -Function *-Ipap*
