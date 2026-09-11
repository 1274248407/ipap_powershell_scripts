#Requires -Modules Pester

<#
.SYNOPSIS
    IPAP 模块 - Test-SupportedImageFormat 单元测试
.DESCRIPTION
    测试 Test-SupportedImageFormat 函数的管道输入、参数验证和边界情况。
#>

Describe 'Test-SupportedImageFormat Unit Tests' -Tag 'Test-SupportedImageFormat', 'IPAP' {
    BeforeAll {
        # tests\Unit\Public → 项目根（向上三级）
        $ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        Import-Module (Join-Path $ProjectRoot 'source\IPAP.psd1') -Force -Global

        Mock Write-LogEntry -ModuleName IPAP { }



        InModuleScope IPAP {
            $script:IPAPConfigInstance = @{
                App = @{
                    SupportedImageFormats = @('.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.tiff')
                }
            }
        }
    }

    AfterAll {
        Remove-Module 'IPAP' -ErrorAction SilentlyContinue
    }

    Context '直接参数调用 - Direct Parameter Call' {
        It '应正确识别支持的图片格式' {
            $file = [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg' }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $true
        }

        It '应正确识别不支持的格式' {
            $file = [PSCustomObject]@{ Name = 'test.txt'; Extension = '.txt' }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $false
        }

        It '应支持自定义格式列表' {
            $file = [PSCustomObject]@{ Name = 'test.bmp'; Extension = '.bmp' }
            $result = Test-SupportedImageFormat -File $file -SupportedFormats @('.bmp')
            $result | Should -Be $true
        }

        It '自定义格式列表应覆盖默认配置' {
            $file = [PSCustomObject]@{ Name = 'test.jpg'; Extension = '.jpg' }
            $result = Test-SupportedImageFormat -File $file -SupportedFormats @('.png')
            $result | Should -Be $false
        }
    }

    Context '管道输入 - Pipeline Input' {
        It '应正确处理单个管道输入' {
            $file = [PSCustomObject]@{ Name = 'test.png'; Extension = '.png' }
            $result = $file | Test-SupportedImageFormat
            $result | Should -Be $true
        }

        It '应正确处理多个管道输入' {
            $files = @(
                [PSCustomObject]@{ Name = 'test1.jpg'; Extension = '.jpg' },
                [PSCustomObject]@{ Name = 'test2.txt'; Extension = '.txt' },
                [PSCustomObject]@{ Name = 'test3.png'; Extension = '.png' }
            )
            $results = $files | Test-SupportedImageFormat
            $results.Count | Should -Be 3
            $results[0] | Should -Be $true
            $results[1] | Should -Be $false
            $results[2] | Should -Be $true
        }

        It '管道输入应保持顺序' {
            $files = @(
                [PSCustomObject]@{ Name = 'a.txt'; Extension = '.txt' },
                [PSCustomObject]@{ Name = 'b.jpg'; Extension = '.jpg' },
                [PSCustomObject]@{ Name = 'c.txt'; Extension = '.txt' }
            )
            $results = $files | Test-SupportedImageFormat
            $results | Should -Be @($false, $true, $false)
        }
    }

    Context '边界情况 - Boundary Cases' {
        It '输入对象缺少 Extension 属性时应返回 $false' {
            $file = [PSCustomObject]@{ Name = 'test.jpg' }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $false
        }

        It '输入对象 Extension 为 $null 时应返回 $false' {
            $file = [PSCustomObject]@{ Name = 'test'; Extension = $null }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $false
        }

        It '输入对象 Extension 为空字符串时应返回 $false' {
            $file = [PSCustomObject]@{ Name = 'test'; Extension = '' }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $false
        }

        It '扩展名大小写不敏感' {
            $file = [PSCustomObject]@{ Name = 'test.JPG'; Extension = '.JPG' }
            $result = Test-SupportedImageFormat -File $file
            $result | Should -Be $true
        }
    }

    Context '参数绑定测试 - Parameter Binding' {
        It '函数应有 Mandatory 参数 File' {
            $cmd = Get-Command Test-SupportedImageFormat
            $fileParam = $cmd.Parameters['File']
            $fileParam.Attributes.Mandatory | Should -Be $true
        }

        It 'File 参数应支持管道输入' {
            $cmd = Get-Command Test-SupportedImageFormat
            $fileParam = $cmd.Parameters['File']
            $pipelineAttr = $fileParam.Attributes | Where-Object { $PSItem -is [System.Management.Automation.ParameterAttribute] }
            $pipelineAttr.ValueFromPipeline | Should -Be $true
        }

        It '函数应声明 OutputType 为 bool' {
            $cmd = Get-Command Test-SupportedImageFormat
            $outputType = $cmd.OutputType
            $outputType.Type.Name | Should -Contain 'Boolean'
        }
    }
}