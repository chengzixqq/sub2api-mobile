#!/usr/bin/env python3
"""Generate the standalone UI prototype Xcode project (one app target, no dependencies)."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = "Sub2Proto"
SOURCES = "Proto"


def identity(name):
    return hashlib.sha256(("proto:" + name).encode()).hexdigest()[:24].upper()


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

    files, builds = [], []
    for path in sorted((ROOT / SOURCES).rglob("*.swift")):
        rel = path.relative_to(ROOT).as_posix()
        ref = add("file:" + rel, f"isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quoted(rel)}; sourceTree = SOURCE_ROOT;")
        files.append(ref)
        builds.append(add("build:" + rel, f"isa = PBXBuildFile; fileRef = {ref};"))
    resources = []
    assets = ROOT / SOURCES / "Assets.xcassets"
    if assets.exists():
        asset_ref = add("assets", f"isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = {quoted(assets.relative_to(ROOT).as_posix())}; sourceTree = SOURCE_ROOT;")
        files.append(asset_ref)
        resources.append(add("assets:build", f"isa = PBXBuildFile; fileRef = {asset_ref};"))
    sources_group = add("group:sources", f'isa = PBXGroup; children = {refs(files)}; name = {SOURCES}; sourceTree = "<group>";')
    product = add("app:product", f"isa = PBXFileReference; explicitFileType = wrapper.application; path = {NAME}.app; sourceTree = BUILT_PRODUCTS_DIR;")
    products = add("products", f'isa = PBXGroup; children = {refs([product])}; name = Products; sourceTree = "<group>";')
    main_group = add("root", f'isa = PBXGroup; children = {refs([sources_group, products])}; sourceTree = "<group>";')
    phase_sources = add("app:sources", f"isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;")
    phase_frameworks = add("app:frameworks", "isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;")
    phase_resources = add("app:resources", f"isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(resources)}; runOnlyForDeploymentPostprocessing = 0;")

    common = {
        "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "6.0",
        "SWIFT_STRICT_CONCURRENCY": "complete", "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    }
    configurations = {}
    for target in ("project", "app"):
        configs = []
        for name in ("Debug", "Release"):
            settings = dict(common)
            settings.update({
                "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG" if name == "Debug" else "",
                "ONLY_ACTIVE_ARCH": "YES" if name == "Debug" else "NO",
            })
            if target == "app":
                settings.update({
                    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "com.chengzixqq.sub2mobile.uiproto",
                    "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
                    "GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "Sub2 原型",
                    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
                    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                    "CODE_SIGN_STYLE": "Automatic", "CODE_SIGNING_ALLOWED": "NO", "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "0.1",
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
                })
                if assets.exists() and (assets / "AppIcon.appiconset").exists():
                    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            body = " ".join(f"{k} = {quoted(v)};" for k, v in sorted(settings.items()))
            configs.append(add(f"{target}:{name}", f"isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};"))
        configurations[target] = add(target + ":configs", f"isa = XCConfigurationList; buildConfigurations = {refs(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;")

    app_id = add("app:target", f'isa = PBXNativeTarget; buildConfigurationList = {configurations["app"]}; buildPhases = {refs([phase_sources, phase_frameworks, phase_resources])}; buildRules = (); dependencies = (); name = {NAME}; productName = {NAME}; productReference = {product}; productType = "com.apple.product-type.application";')
    project = add("project", f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {app_id} = {{ CreatedOnToolsVersion = 27.0; }}; }}; }}; buildConfigurationList = {configurations["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = "zh-Hans"; hasScannedForEncodings = 0; knownRegions = ("zh-Hans", en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app_id])};')

    project_dir = ROOT / f"{NAME}.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text(
        "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n"
        + "\n".join(objects) + f"\n\t}};\n\trootObject = {project};\n}}\n", encoding="utf-8")
    scheme_dir = project_dir / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_id}" BuildableName="{NAME}.app" BlueprintName="{NAME}" ReferencedContainer="container:{NAME}.xcodeproj"/>'
    (scheme_dir / f"{NAME}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
</Scheme>
''', encoding="utf-8")
    print(f"Generated {project_dir} ({len(files)} files)")


if __name__ == "__main__":
    generate()
