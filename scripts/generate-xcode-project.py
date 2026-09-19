#!/usr/bin/env python3
"""Regenerate the checked-in native app project after adding Swift source files.

No XcodeGen/Ruby dependency. SwiftPM remains the direct-distribution build.
"""
from hashlib import sha1
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'TokensOnTrack.xcodeproj'
objects = {}

def ident(name):
    return sha1(name.encode()).hexdigest()[:24].upper()

def add(key, **fields):
    objects[ident(key)] = fields
    return ident(key)

def ref(path, kind, tree='<group>'):
    return add(path, isa='PBXFileReference', lastKnownFileType=kind, path=path, sourceTree=tree)

def build(path, file):
    return add('build:' + path, isa='PBXBuildFile', fileRef=file)

sources = sorted(p.relative_to(ROOT).as_posix() for p in (ROOT / 'Sources/AIUsage').glob('*.swift'))
source_refs = [ref(p, 'sourcecode.swift') for p in sources]
resources = [('Resources/AppIcon.icns', 'image.icns'), ('Resources/Icons', 'folder'),
             ('Resources/PrivacyInfo.xcprivacy', 'text.xml'), ('Resources/Privacy.html', 'text.html')]
resource_refs = [ref(p, kind) for p, kind in resources]
config_refs = {c: ref(f'Config/{c}.xcconfig', 'text.xcconfig') for c in ('Debug', 'AppStore')}
extra_refs = [ref('Config/Store.xcconfig', 'text.xcconfig'), ref('Config/AppStore.entitlements', 'text.plist.entitlements'),
              ref('Config/ExportOptions.plist', 'text.plist.xml'), ref('Resources/Info.plist', 'text.plist.xml')]
product = add('product', isa='PBXFileReference', explicitFileType='wrapper.application', includeInIndex=0,
              path='Tokens on Track.app', sourceTree='BUILT_PRODUCTS_DIR')
products = add('products', isa='PBXGroup', children=[product], name='Products', sourceTree='<group>')
root = add('root', isa='PBXGroup', children=source_refs + resource_refs + list(config_refs.values()) + extra_refs + [products], sourceTree='<group>')
source_phase = add('sources', isa='PBXSourcesBuildPhase', buildActionMask=2147483647,
                   files=[build(p, r) for p, r in zip(sources, source_refs)], runOnlyForDeploymentPostprocessing=0)
resources_phase = add('resources', isa='PBXResourcesBuildPhase', buildActionMask=2147483647,
                      files=[build(p, r) for (p, _), r in zip(resources, resource_refs)], runOnlyForDeploymentPostprocessing=0)
frameworks = add('frameworks', isa='PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
stamp = add('stamp', isa='PBXShellScriptBuildPhase', alwaysOutOfDate=1, buildActionMask=2147483647,
            files=[], inputPaths=['$(SRCROOT)/Resources/Info.plist', '$(SRCROOT)/versioning.py', '$(SRCROOT)/scripts/store-info.py'],
            outputPaths=['$(DERIVED_FILE_DIR)/AppStore-Info.plist'], name='Generate Store Info.plist',
            runOnlyForDeploymentPostprocessing=0, shellPath='/bin/sh',
            shellScript='set -eu\n/usr/bin/xcrun python3 "$SRCROOT/scripts/store-info.py"\n')
project_configs = []
target_configs = []
for config in ('Debug', 'AppStore'):
    project_configs.append(add('project:' + config, isa='XCBuildConfiguration', name=config,
                               buildSettings={'CLANG_ENABLE_MODULES': 'YES', 'SDKROOT': 'macosx'}))
    target_configs.append(add('target:' + config, isa='XCBuildConfiguration', name=config,
                              baseConfigurationReference=config_refs[config], buildSettings={}))
pcl = add('project-configs', isa='XCConfigurationList', buildConfigurations=project_configs,
          defaultConfigurationIsVisible=0, defaultConfigurationName='AppStore')
tcl = add('target-configs', isa='XCConfigurationList', buildConfigurations=target_configs,
          defaultConfigurationIsVisible=0, defaultConfigurationName='AppStore')
target = add('app-target', isa='PBXNativeTarget', buildConfigurationList=tcl,
             buildPhases=[stamp, source_phase, frameworks, resources_phase], buildRules=[], dependencies=[],
             name='Tokens on Track', productName='Tokens on Track', productReference=product,
             productType='com.apple.product-type.application')
project = add('project', isa='PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '2700',
              'TargetAttributes': {target: {'CreatedOnToolsVersion': '27.0', 'DevelopmentTeam': '3F5CFS4B2T', 'ProvisioningStyle': 'Automatic',
              'SystemCapabilities': {'com.apple.Sandbox': {'enabled': 1}}}}},
              buildConfigurationList=pcl, compatibilityVersion='Xcode 14.0', developmentRegion='en',
              hasScannedForEncodings=0, knownRegions=['en', 'Base'], mainGroup=root, productRefGroup=products,
              projectDirPath='', projectRoot='', targets=[target])

def encode(value, level=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t'*(level+1) + json.dumps(k) + ' = ' + encode(v, level+1) + ';\n' for k,v in value.items()) + '\t'*level + '}'
    if isinstance(value, list):
        return '(' + ', '.join(encode(v, level) for v in value) + (',' if value else '') + ')'
    return str(value) if isinstance(value, int) else json.dumps(value)

PROJECT.mkdir(exist_ok=True)
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + encode({'archiveVersion': 1, 'classes': {}, 'objectVersion': 56, 'objects': objects, 'rootObject': project}) + '\n')
schemes = PROJECT / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Tokens on Track.app" BlueprintName="Tokens on Track" ReferencedContainer="container:TokensOnTrack.xcodeproj"/>'
(schemes / 'Tokens on Track.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="AppStore" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="AppStore" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated {PROJECT.name} with {len(sources)} Swift sources')
