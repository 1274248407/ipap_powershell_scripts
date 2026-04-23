# 创建打包目录
$packageDir = 'IPAP_Package'
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

# 复制核心模块
Copy-Item -Path 'Modules' -Destination "$packageDir\Modules" -Recurse
Copy-Item -Path 'Main.ps1' -Destination "$packageDir\"

# 复制二进制依赖
Copy-Item -Path 'bin' -Destination "$packageDir\bin" -Recurse

# 复制配置模板
Copy-Item -Path 'config.toml.example' -Destination "$packageDir\config.toml"

Write-Host "打包完成，目录: $packageDir"
