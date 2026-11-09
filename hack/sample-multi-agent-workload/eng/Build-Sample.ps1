# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

[CmdletBinding()]
param([string]$Image = 'sample-workload:local')
$ErrorActionPreference = 'Stop'
& az bicep build --file "$PSScriptRoot/../infra/main.bicep" --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Sample infrastructure compilation failed.' }
& docker build --tag $Image (Split-Path $PSScriptRoot -Parent)
if ($LASTEXITCODE -ne 0) { throw 'Sample container build failed.' }
