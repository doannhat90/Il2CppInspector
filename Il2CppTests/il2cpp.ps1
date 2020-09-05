﻿# Copyright 2019-2020 Katy Coe - http://www.djkaty.com - https://github.com/djkaty
# All rights reserved.

# Compile the specified .cs files in TestSources to produce a .NET assembly DLL, the transpiled C++ source code and an IL2CPP binary for each
# Requires Unity 2018.3.0f2 or later and Visual Studio 2017 (or MSBuild with C# 7+ support) or later to be installed
# Requires Android NDK r13b or newer for Android test builds (https://developer.android.com/ndk/downloads)

param (
	# Which source files in TestSources to generate aseemblies, C++ and IL2CPP binaries for
	[string[]] $assemblies = "*",

	# Which Unity version to use; uses the latest installed if not specified
	[string] $unityVersion = "*"
)

$ErrorActionPreference = "SilentlyContinue"

# Function to compare two Unity versions
function Compare-UnityVersions {
	param (
		[string] $left,
		[string] $right
	)
	$rgx = '^(?<major>[0-9]{1,4})\.(?<minor>[0-6])\.(?<build>[0-9]{1,2}).*$'
	if ($left -notmatch $rgx) {
		Write-Error "Invalid Unity version number"
		Exit
	}
	$leftVersion = $Matches
	if ($right -notmatch $rgx) {
		Write-Error "Invalid Unity version number"
		Exit
	}
	$rightVersion = $Matches

	if ($leftVersion.major -ne $rightVersion.major) {
		return $leftVersion.major - $rightVersion.major
	}
	if ($leftVersion.minor -ne $rightVersion.minor) {
		return $leftVersion.minor - $rightVersion.minor
	}
	$leftVersion.build - $rightVersion.build
}

# If supplied Unity version is a path, use it, otherwise assume default path from version number alone
if ($unityVersion -match "[\\/]") {
	$UnityFolder = $unityVersion
} else {
	# The introduction of Unity Hub changed the base path of the Unity editor
	$UnityFolder = "$env:ProgramFiles\Unity\Hub\Editor\$unityVersion"
}

# Look for Unity Roslyn installs
$CSC = (gci "$UnityFolder\Editor\Data\Tools\Roslyn\csc.exe" | sort FullName)[-1].FullName
# Look for .NET Framework installs
$CSC = (gci "${env:ProgramFiles(x86)}\MSBuild\*\Bin\csc.exe" | sort FullName)[-1].FullName

# Look for Visual Studio Roslyn installs (14.0 = Visual Studio 2017, 15.0 = Visual Studio 2019 etc.)
# These are ordered from least to most preferred. If no files exist at the specified path,
# a silent exception will be thrown and the variable will not be re-assigned.
$CSC = (gci "${env:ProgramFiles(x86)}\Microsoft Visual Studio\*\*\MSBuild\*\Bin\Roslyn\csc.exe" | sort FullName)[-1].FullName

# Path to latest installed version of Unity
$UnityPath = (gi "$UnityFolder\Editor\Data" | sort FullName)[-1].FullName

# Path to il2cpp.exe
# For Unity <= 2019.2.21f1, il2cpp\build\il2cpp.exe
# For Unity >= 2019.3.0f6, il2cpp\build\deploy\net471\il2cpp.exe
$il2cpp = (gci "$UnityPath\il2cpp\build" -Recurse -Filter il2cpp.exe)[0].FullName

# Path to bytecode stripper
$stripper = (gci "$UnityPath\il2cpp\build" -Recurse -Filter UnityLinker.exe)[0].FullName

# Path to mscorlib.dll
# For Unity <= 2018.1.9f2, Mono\lib\mono\2.0\...
# For Unity >= 2018.2.0f2, MonoBleedingEdge\lib\mono\unityaot\...
$mscorlib = (gci "$UnityPath\Mono*\lib\mono\unityaot\mscorlib.dll")[0].FullName

# Determine the actual Unity version
$actualUnityVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo("$UnityFolder\Editor\Unity.exe").FileVersion

# For Unity >= 2020.1.0f1, we need baselib
if ($actualUnityVersion -and (Compare-UnityVersions $actualUnityVersion 2020.1.0) -ge 0) {
	$baselibX64 = $UnityPath + '\PlaybackEngines\windowsstandalonesupport\Variations\win64_nondevelopment_il2cpp'
	if (Test-Path -Path $baselibX64 -PathType container) {
		$baselibX64Arg = "--baselib-directory=$baselibX64"
	}

	$baselibX86 = $UnityPath + '\PlaybackEngines\windowsstandalonesupport\Variations\win32_nondevelopment_il2cpp'
	if (Test-Path -Path $baselibX86 -PathType container) {
		$baselibX86Arg = "--baselib-directory=$baselibX86"
	}

	$baselibARM64 = $UnityPath + '\PlaybackEngines\AndroidPlayer\Variations\il2cpp\Release\StaticLibs\arm64-v8a'
	if (Test-Path -Path $baselibARM64 -PathType container) {
		$baselibARM64Arg = "--baselib-directory=$baselibARM64"
	}

	$baselibARMv7 = $UnityPath + '\PlaybackEngines\AndroidPlayer\Variations\il2cpp\Release\StaticLibs\armeabi-v7a'
	if (Test-Path -Path $baselibARMv7 -PathType container) {
		$baselibARMv7Arg = "--baselib-directory=$baselibARMv7"
	}
}

# Path to the Android NDK
# Different Unity versions require specific NDKs, see the section Change the NDK at:
# The NDK can also be installed standalone without AndroidPlayer
# https://docs.unity3d.com/2019.1/Documentation/Manual/android-sdksetup.html
$AndroidPlayer = $UnityPath + '\PlaybackEngines\AndroidPlayer'
$AndroidNDK = $AndroidPlayer + '\NDK'
$AndroidBuildEnabled = $True

$ErrorActionPreference = "Continue"

# Check that everything is installed
if (!$CSC) {
	Write-Error "Could not find C¤ compiler csc.exe - aborting"
	Exit
}

if (!$actualUnityVersion) {
	Write-Error "Could not find Unity editor - aborting"
	Exit
}

if (!(Test-Path -Path $AndroidNDK -PathType container)) {
	echo "Could not find Android NDK at '$AndroidNDK'"
	$AndroidBuildEnabled = $False
}

if (!$il2cpp) {
	Write-Error "Could not find Unity IL2CPP build support - aborting"
	Exit
}

if (!$stripper) {
	Write-Error "Could not find Unity IL2CPP bytecode stripper - aborting"
	Exit
}

if (!$mscorlib) {
	Write-Error "Could not find Unity mscorlib assembly - aborting"
	Exit
}

if (!(Test-Path -Path $AndroidPlayer -PathType container)) {
	echo "Could not find Unity Android build support at '$AndroidPlayer'"
	$AndroidBuildEnabled = $False
}

echo "Using C# compiler at '$CSC'"
echo "Using Unity installation at '$UnityPath'"
echo "Using IL2CPP toolchain at '$il2cpp'"
echo "Using Unity mscorlib assembly at '$mscorlib'"

if ($AndroidBuildEnabled) {
	echo "Using Android player at '$AndroidPlayer'"
	echo "Using Android NDK at '$AndroidNDK'"
} else {
	echo "Android build is disabled due to missing components"
}

echo "Targeted Unity version: $actualUnityVersion"

# Workspace paths
$src = "$PSScriptRoot/TestSources"
$asm = "$PSScriptRoot/TestAssemblies"
$cpp = "$PSScriptRoot/TestCpp"
$bin = "$PSScriptRoot/TestBinaries"

# We try to make the arguments as close as possible to a real Unity build
# "--lump-runtime-library" was added to reduce the number of C++ files generated by UnityEngine (Unity 2019)
# "--disable-runtime-lumping" replaced the above (Unity 2019.3)
$cppArg =		'--convert-to-cpp', '-emit-null-checks', '--enable-array-bounds-check', '--dotnetprofile="unityaot"'

$compileArg =	'--compile-cpp', '--libil2cpp-static', '--configuration=Release', `
				'--map-file-parser=$UnityPath\il2cpp\MapFileParser\MapFileParser.exe', '--dotnetprofile="unityaot"', `
				'--forcerebuild'

# Prepare output folders
md $asm, $bin 2>&1 >$null

# Compile all specified .cs files in TestSources
echo "Compiling source code..."

$cs = $assemblies | % {"$_.cs"}
gci "$src/*" -Include $cs | % {
	echo "$($_.Name) -> $($_.BaseName).dll"

	& $csc "/t:library" "/nologo" "/unsafe" "/out:$asm/$($_.BaseName).dll" "$_"
	
	if ($LastExitCode -ne 0) {
		Write-Error "Compilation error - aborting"
		Exit
	}
}

# Strip each assembly of unnecessary code to reduce compile time
$dll = $assemblies | % {"$_.dll"}

gci "$asm/*" -Include $dll | % {
	$name = $_.Name
	echo "Running bytecode stripper on $name..."

	& $stripper	"--out=$asm/$($_.BaseName)-stripped", "--i18n=none", "--core-action=link", `
				"--include-assembly=$_,$mscorlib", "--dotnetruntime=il2cpp", "--dotnetprofile=unityaot", `
				"--use-editor-options"
}

# Transpile all of the DLLs to C++
# We split this up from the binary compilation phase to avoid unnecessary DLL -> C++ transpiles for the same application
gci "$asm/*" -Include $dll | % {
	$name = $_.BaseName
	echo "Converting assembly $($_.Name) to C++..."
	rm -Force -Recurse $cpp/$name 2>&1 >$null
	& $il2cpp $cppArg "--generatedcppdir=$cpp/$name", "--assembly=$asm/$($_.BaseName)-stripped/$($_.Name)" >$null
}

# Run IL2CPP on all generated assemblies for both x86 and ARM
# Earlier builds of Unity included mscorlib.dll automatically; in current versions we must specify its location
function Do-IL2CPP-Build {
	param (
		[string] $Platform,
		[string] $Architecture,
		[string] $Name,
		$AdditionalArgs
	)

	# Determine target name
	$prefix = if ($Architecture -eq 'x86' -or $Architecture -eq 'x64') {'GameAssembly-'}
	$ext = if ($Architecture -eq 'x86' -or $Architecture -eq 'x64') {"dll"} else {"so"}
	$TargetBaseName = "$prefix$Name-$Architecture"

	echo "Running il2cpp compiler for $TargetBaseName ($Platform/$Architecture)..."

	# Compile
	md $bin/$TargetBaseName 2>&1 >$null
	md $bin/$TargetBaseName/cache 2>&1 >$null

	& $il2cpp $compileArg $AdditionalArgs "--platform=$Platform", "--architecture=$Architecture", `
				"--outputpath=$bin/$TargetBaseName/$TargetBaseName.$ext", `
				"--generatedcppdir=$cpp/$Name", `
				"--cachedirectory=$bin/$TargetBaseName/cache" >$null

	if ($LastExitCode -ne 0) {
		Write-Error "IL2CPP error - aborting"
		Exit
	}

	mv -Force $bin/$TargetBaseName/Data/metadata/global-metadata.dat $bin/$TargetBaseName
	rm -Force -Recurse $bin/$TargetBaseName/Data
	rm -Force -Recurse $bin/$TargetBaseName/cache
}

# Generate build for each target platform and architecture
gci "$asm/*" -Include $dll | % {
	# x86
	Do-IL2CPP-Build WindowsDesktop x86 $_.BaseName $baselibX86Arg

	# x64
	Do-IL2CPP-Build WindowsDesktop x64 $_.BaseName $baselibX64Arg

	# ARMv7
	if ($AndroidBuildEnabled) {
		Do-IL2CPP-Build Android ARMv7 $_.BaseName $baselibARMv7Arg, `
					"--additional-include-directories=$AndroidPlayer/Tools/bdwgc/include", `
					"--additional-include-directories=$AndroidPlayer/Tools/libil2cpp/include", `
					"--tool-chain-path=$AndroidNDK"
	}

	# ARMv8 / A64
	if ($AndroidBuildEnabled) {
		Do-IL2CPP-Build Android ARM64 $_.BaseName $baselibARM64Arg, `
					"--additional-include-directories=$AndroidPlayer/Tools/bdwgc/include", `
					"--additional-include-directories=$AndroidPlayer/Tools/libil2cpp/include", `
					"--tool-chain-path=$AndroidNDK"
	}
}

# Generate test stubs
& "$PSScriptRoot/generate-tests.ps1"
