#!/usr/bin/env python3
"""Generate the checked-in, dependency-free standard Xcode project deterministically."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil

ROOT = Path(__file__).resolve().parents[1]


def identity(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()


def quoted(value):
    return json.dumps(str(value))


def generate():
    objects = []

    def add(name, body):
        key = identity(name)
        objects.append(f"\t\t{key} = {{ {body} }};")
        return key

    def refs(keys):
        return "(" + ", ".join(keys) + ",)" if keys else "()"

    source_groups = {}
    for directory in ("NativeApp", "UITests"):
        files, builds = [], []
        for path in sorted((ROOT / directory).rglob("*.swift")):
            rel = path.relative_to(ROOT).as_posix()
            ref = add("file:" + rel, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(rel)}; sourceTree = SOURCE_ROOT;")
            files.append(ref)
            builds.append(add("build:" + rel, f"isa = PBXBuildFile; fileRef = {ref};"))
        group = add("group:" + directory, f"isa = PBXGroup; children = {refs(files)}; name = {directory}; sourceTree = \"<group>\";")
        source_groups[directory] = (group, builds)
    assets = ROOT / "NativeApp/Resources/Assets.xcassets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    shutil.copytree(ROOT / "icons/ios/AppIcon.appiconset", assets / "AppIcon.appiconset", dirs_exist_ok=True)
    asset_ref = add("assets", 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = NativeApp/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
    asset_build = add("assets:build", f"isa = PBXBuildFile; fileRef = {asset_ref};")
    app_product = add("app:product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Sub2Mobile.app; sourceTree = BUILT_PRODUCTS_DIR;')
    test_product = add("test:product", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = Sub2MobileUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    products = add("products", f'isa = PBXGroup; children = {refs([app_product, test_product])}; name = Products; sourceTree = "<group>";')
    group = add("root", f'isa = PBXGroup; children = {refs([source_groups["NativeApp"][0], source_groups["UITests"][0], asset_ref, products])}; sourceTree = "<group>";')
    package = add("package", 'isa = XCLocalSwiftPackageReference; relativePath = ".";')
    core = add("core", f"isa = XCSwiftPackageProductDependency; package = {package}; productName = Sub2Core;")
    core_build = add("core:build", f"isa = PBXBuildFile; productRef = {core};")
    app_sources = add("app:sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(source_groups['NativeApp'][1])}; runOnlyForDeploymentPostprocessing = 0;")
    app_frameworks = add("app:frameworks", f"isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs([core_build])}; runOnlyForDeploymentPostprocessing = 0;")
    app_resources = add("app:resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs([asset_build])}; runOnlyForDeploymentPostprocessing = 0;")
    test_sources = add("test:sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(source_groups['UITests'][1])}; runOnlyForDeploymentPostprocessing = 0;")
    test_frameworks = add("test:frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    configurations = {}
    common = {"IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "6.0", "SWIFT_STRICT_CONCURRENCY": "complete", "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES"}
    for target in ("project", "app", "test"):
        configs = []
        for name in ("Debug", "Release"):
            settings = dict(common)
            settings.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else ""})
            if target != "project":
                settings.update({"PRODUCT_NAME": "$(TARGET_NAME)", "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_STYLE": "Automatic", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0"})
            if target == "app":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "com.chengzixqq.sub2mobile", "INFOPLIST_FILE": "NativeApp/Resources/Info.plist", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"})
            elif target == "test":
                settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "com.chengzixqq.sub2mobile.uitests", "TEST_TARGET_NAME": "Sub2Mobile", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"})
            body = " ".join(f"{k} = {quoted(v)};" for k, v in sorted(settings.items()))
            configs.append(add(target + ":" + name, f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};"))
        configurations[target] = add(target + ":configs", f"isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    app_id = identity("app:target")
    proxy = add("test:proxy", f"isa = PBXContainerItemProxy; containerPortal = {identity('project')}; proxyType = 1; remoteGlobalIDString = {app_id}; remoteInfo = Sub2Mobile;")
    dependency = add("test:dependency", f"isa = PBXTargetDependency; target = {app_id}; targetProxy = {proxy};")
    add("app:target", f"isa = PBXNativeTarget; buildConfigurationList = {configurations['app']}; buildPhases = {refs([app_sources, app_frameworks, app_resources])}; buildRules = (); dependencies = (); name = Sub2Mobile; packageProductDependencies = {refs([core])}; productName = Sub2Mobile; productReference = {app_product}; productType = \"com.apple.product-type.application\";")
    test_id = add("test:target", f"isa = PBXNativeTarget; buildConfigurationList = {configurations['test']}; buildPhases = {refs([test_sources, test_frameworks])}; buildRules = (); dependencies = {refs([dependency])}; name = Sub2MobileUITests; productName = Sub2MobileUITests; productReference = {test_product}; productType = \"com.apple.product-type.bundle.ui-testing\";")
    project = add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 27.0; }}; {test_id} = {{ CreatedOnToolsVersion = 27.0; TestTargetID = {app_id}; }}; }}; }}; buildConfigurationList = {configurations["project"]}; compatibilityVersion = "Xcode 16.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {group}; packageReferences = {refs([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app_id, test_id])};')
    project_dir = ROOT / "Sub2Mobile.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 77;\n\tobjects = {\n" + "\n".join(objects) + f"\n\t}};\n\trootObject = {project};\n}}\n", encoding="utf-8")
    scheme_dir = project_dir / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    def reference(key, product, target):
        return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{product}" BlueprintName="{target}" ReferencedContainer="container:Sub2Mobile.xcodeproj"/>'
    app_ref = reference(app_id, "Sub2Mobile.app", "Sub2Mobile")
    test_ref = reference(test_id, "Sub2MobileUITests.xctest", "Sub2MobileUITests")
    (scheme_dir / "Sub2Mobile.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
    <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''', encoding="utf-8")
    info = {"CFBundleDisplayName": "Sub2 Mobile", "LSRequiresIPhoneOS": True, "ITSAppUsesNonExemptEncryption": False, "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"], "UISupportedInterfaceOrientations~ipad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]}
    with (ROOT / "NativeApp/Resources/Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    print(f"Generated {project_dir} ({len(objects)} objects)")


if __name__ == "__main__":
    generate()
