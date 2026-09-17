#!/usr/bin/env python3
"""Regenerate the Xcode project from the source tree."""
import hashlib, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[1]
objects = {}
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def obj(key, value):
    ident = uid(key); objects[ident] = value; return ident
def q(s): return '"' + str(s).replace('\\','\\\\').replace('"','\\"') + '"'
def arr(items): return '(' + ', '.join(items) + ')'
def group(path):
    children = []
    for f in sorted(path.iterdir()):
        if f.is_dir() and f.suffix != '.xcassets': children.append(group(f))
        else:
            typ = 'sourcecode.swift' if f.suffix == '.swift' else 'folder.assetcatalog' if f.suffix == '.xcassets' else 'text.plist.entitlements' if f.suffix == '.entitlements' else 'text.plist.xml'
            children.append(obj(str(f.relative_to(ROOT)), '{isa = PBXFileReference; lastKnownFileType = '+typ+'; path = '+q(f.name)+'; sourceTree = "<group>";}'))
    return obj('group:'+str(path.relative_to(ROOT)), '{isa = PBXGroup; children = '+arr(children)+'; path = '+q(path.name)+'; sourceTree = "<group>";}')
source_group = group(ROOT/'Nexa'); tests_group = group(ROOT/'NexaTests')
app_product = obj('product-app', '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Nexa.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product = obj('product-test', '{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = NexaTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products = obj('products', '{isa = PBXGroup; children = '+arr([app_product,test_product])+'; name = Products; sourceTree = "<group>";}')
main = obj('main-group', '{isa = PBXGroup; children = '+arr([source_group,tests_group,products])+'; sourceTree = "<group>";}')
def phase(name, kind, paths):
    files = [obj('build:'+str(p.relative_to(ROOT)), '{isa = PBXBuildFile; fileRef = '+uid(str(p.relative_to(ROOT)))+';}') for p in paths]
    return obj('phase:'+name, '{isa = '+kind+'; buildActionMask = 2147483647; files = '+arr(files)+'; runOnlyForDeploymentPostprocessing = 0;}')
app_sources = phase('app-src','PBXSourcesBuildPhase', sorted((ROOT/'Nexa').rglob('*.swift')))
resources = phase('resources','PBXResourcesBuildPhase',[ROOT/'Nexa/Resources/Assets.xcassets'])
test_sources = phase('test-src','PBXSourcesBuildPhase',sorted((ROOT/'NexaTests').rglob('*.swift')))
common = {'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'15.0','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','CODE_SIGN_STYLE':'Manual','CODE_SIGN_IDENTITY':'-','DEVELOPMENT_TEAM':'','SWIFT_STRICT_CONCURRENCY':'minimal','ENABLE_USER_SCRIPT_SANDBOXING':'NO'}
def configlist(name, settings):
    configs = []
    for config in ['Debug','Release']:
        values = dict(common); values.update(settings); values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym','ONLY_ACTIVE_ARCH':'YES' if config=='Debug' else 'NO','ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO'})
        if config=='Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        configs.append(obj('config:'+name+config,'{isa = XCBuildConfiguration; buildSettings = {'+' '.join(k+' = '+q(v)+';' for k,v in values.items())+'}; name = '+config+';}'))
    return obj('config-list:'+name, '{isa = XCConfigurationList; buildConfigurations = '+arr(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
project_configs = configlist('project', {})
app_configs = configlist('app', {'PRODUCT_NAME':'Nexa','PRODUCT_BUNDLE_IDENTIFIER':'app.nexa.mac','INFOPLIST_FILE':'Nexa/Resources/Info.plist','CODE_SIGN_ENTITLEMENTS':'Nexa/Resources/Nexa.entitlements','ENABLE_HARDENED_RUNTIME':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','GENERATE_INFOPLIST_FILE':'NO','COMBINE_HIDPI_IMAGES':'YES'})
test_configs = configlist('test', {'PRODUCT_NAME':'NexaTests','PRODUCT_BUNDLE_IDENTIFIER':'app.nexa.mac.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Nexa.app/Contents/MacOS/Nexa','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks'})
bridge = obj('phase:bridge', '{isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); name = "Build local media bridge"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/bash; shellScript = '+q('bash "$SRCROOT/Scripts/build-media-bridge.sh"')+'; alwaysOutOfDate = 1;}')
app_target = obj('target-app','{isa = PBXNativeTarget; buildConfigurationList = '+app_configs+'; buildPhases = '+arr([app_sources,resources,bridge])+'; buildRules = (); dependencies = (); name = Nexa; productName = Nexa; productReference = '+app_product+'; productType = "com.apple.product-type.application";}')
proxy = obj('proxy','{isa = PBXContainerItemProxy; containerPortal = '+uid('project')+'; proxyType = 1; remoteGlobalIDString = '+app_target+'; remoteInfo = Nexa;}')
dependency = obj('dependency','{isa = PBXTargetDependency; target = '+app_target+'; targetProxy = '+proxy+';}')
test_target = obj('target-test','{isa = PBXNativeTarget; buildConfigurationList = '+test_configs+'; buildPhases = '+arr([test_sources])+'; buildRules = (); dependencies = '+arr([dependency])+'; name = NexaTests; productName = NexaTests; productReference = '+test_product+'; productType = "com.apple.product-type.bundle.unit-test";}')
project = obj('project','{isa = PBXProject; attributes = {LastUpgradeCheck = 2600; TargetAttributes = {'+app_target+' = {CreatedOnToolsVersion = 26.0;}; '+test_target+' = {CreatedOnToolsVersion = 26.0; TestTargetID = '+app_target+';};};}; buildConfigurationList = '+project_configs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = '+main+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+arr([app_target,test_target])+';}')
(ROOT/'Nexa.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+'; }\n')
def ref(target, name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Nexa.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app_target,'Nexa.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ref(test_target,'NexaTests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Nexa.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app_target,'Nexa.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>'''
(ROOT/'Nexa.xcodeproj/xcshareddata/xcschemes/Nexa.xcscheme').write_text(scheme)
print('Generated Nexa.xcodeproj')
