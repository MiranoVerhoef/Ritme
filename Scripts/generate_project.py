#!/usr/bin/env python3
"""Generate a dependency-free Xcode project for the iPhone, Watch and tests."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def add(key, value):
    identifier = hashlib.sha1(key.encode()).hexdigest()[:24].upper()
    objects[identifier] = value
    return identifier

def encode(value):
    if isinstance(value, dict):
        return "{ " + " ".join(f"{json.dumps(k)} = {encode(v)};" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "( " + ", ".join(encode(v) for v in value) + " )"
    return json.dumps(str(value))

def file(path, kind):
    return add("file:" + path, {"isa": "PBXFileReference", "lastKnownFileType": kind, "path": path, "sourceTree": "SOURCE_ROOT"})

def config_list(name, settings):
    configs = []
    for mode in ["Debug", "Release"]:
        values = dict(settings)
        values.update({"SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O", "DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym"})
        if mode == "Debug": values["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        configs.append(add(name + ":" + mode, {"isa": "XCBuildConfiguration", "name": mode, "buildSettings": values}))
    return add(name + ":configs", {"isa": "XCConfigurationList", "buildConfigurations": configs, "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})

products = []
groups = []
targets = {}
project_id = hashlib.sha1(b"project").hexdigest()[:24].upper()

def target(name, folder, bundle, product_type, extension, sdk, extra):
    source_files = sorted(ROOT.glob(folder + "/**/*.swift"))
    references = [file(str(p.relative_to(ROOT)), "sourcecode.swift") for p in source_files]
    sources = add(name + ":sources", {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": [add(name + ":build:" + ref, {"isa": "PBXBuildFile", "fileRef": ref}) for ref in references], "runOnlyForDeploymentPostprocessing": 0})
    frameworks = add(name + ":frameworks", {"isa": "PBXFrameworksBuildPhase", "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0})
    resources = add(name + ":resources", {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647, "files": [], "runOnlyForDeploymentPostprocessing": 0})
    product = add(name + ":product", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application" if extension == "app" else "wrapper.cfbundle", "includeInIndex": 0, "path": name + "." + extension, "sourceTree": "BUILT_PRODUCTS_DIR"})
    products.append(product)
    settings = {"PRODUCT_NAME": name, "PRODUCT_BUNDLE_IDENTIFIER": bundle, "SDKROOT": sdk, "SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "NO", "CURRENT_PROJECT_VERSION": 1, "MARKETING_VERSION": "0.1.0", "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks"}
    settings.update(extra)
    identifier = add(name + ":target", {"isa": "PBXNativeTarget", "name": name, "productName": name, "productReference": product, "productType": product_type, "buildConfigurationList": config_list(name, settings), "buildPhases": [sources, frameworks, resources], "buildRules": [], "dependencies": []})
    groups.append(add(name + ":group", {"isa": "PBXGroup", "name": name, "children": references, "sourceTree": "<group>"}))
    targets[name] = identifier
    return identifier

app = target("Ritme", "Ritme/Sources", "nl.verhoef.ritme", "com.apple.product-type.application", "app", "iphoneos", {"INFOPLIST_FILE": "Ritme/Resources/Info.plist", "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO"})
asset = file("Ritme/Resources/Assets.xcassets", "folder.assetcatalog")
objects[groups[0]]["children"].append(asset)
objects[hashlib.sha1(b"Ritme:resources").hexdigest()[:24].upper()]["files"].append(add("app-assets-build", {"isa": "PBXBuildFile", "fileRef": asset}))
for config in objects[objects[app]["buildConfigurationList"]]["buildConfigurations"]:
    objects[config]["buildSettings"]["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
watch = target("RitmeWatch", "RitmeWatch", "nl.verhoef.ritme.watchkitapp", "com.apple.product-type.application", "app", "watchos", {"INFOPLIST_FILE": "RitmeWatch/Info.plist", "WATCHOS_DEPLOYMENT_TARGET": "11.0", "TARGETED_DEVICE_FAMILY": "4", "SUPPORTED_PLATFORMS": "watchos watchsimulator", "SKIP_INSTALL": "YES"})
tests = target("RitmeTests", "RitmeTests", "nl.verhoef.ritme.tests", "com.apple.product-type.bundle.unit-test", "xctest", "iphoneos", {"GENERATE_INFOPLIST_FILE": "YES", "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "TARGETED_DEVICE_FAMILY": "1", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Ritme.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Ritme", "BUNDLE_LOADER": "$(TEST_HOST)", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator"})

def dependency(owner, other, name):
    proxy = add(name + ":proxy", {"isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": 1, "remoteGlobalIDString": other, "remoteInfo": objects[other]["name"]})
    dep = add(name + ":dependency", {"isa": "PBXTargetDependency", "target": other, "targetProxy": proxy})
    objects[owner]["dependencies"].append(dep)

dependency(app, watch, "app-watch")
dependency(tests, app, "tests-app")
embed = add("embed-watch", {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": 2147483647, "dstPath": "$(CONTENTS_FOLDER_PATH)/Watch", "dstSubfolderSpec": 16, "name": "Embed Watch Content", "files": [add("embed-watch-file", {"isa": "PBXBuildFile", "fileRef": objects[watch]["productReference"], "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})], "runOnlyForDeploymentPostprocessing": 0})
objects[app]["buildPhases"].append(embed)

resources_refs = [file("Ritme/Resources/Info.plist", "text.plist.xml"), file("Ritme/Resources/Ritme.entitlements", "text.plist.entitlements"), file("RitmeWatch/Info.plist", "text.plist.xml")]
groups.append(add("resources-group", {"isa": "PBXGroup", "name": "Configuration", "children": resources_refs, "sourceTree": "<group>"}))
product_group = add("products", {"isa": "PBXGroup", "name": "Products", "children": products, "sourceTree": "<group>"})
main = add("main", {"isa": "PBXGroup", "children": groups + [product_group], "sourceTree": "<group>"})
project_settings = {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SWIFT_VERSION": "5.0", "ENABLE_TESTABILITY": "YES"}
objects[project_id] = {"isa": "PBXProject", "attributes": {"LastUpgradeCheck": "2700", "BuildIndependentTargetsInParallel": "YES"}, "buildConfigurationList": config_list("Project", project_settings), "compatibilityVersion": "Xcode 14.0", "developmentRegion": "en", "knownRegions": ["en", "Base"], "mainGroup": main, "productRefGroup": product_group, "projectDirPath": "", "projectRoot": "", "targets": [app, watch, tests]}
project = ROOT / "Ritme.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
def ref(identifier, name, filename):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{identifier}" BuildableName="{filename}" BlueprintName="{name}" ReferencedContainer="container:Ritme.xcodeproj"/>'
app_ref = ref(app, "Ritme", "Ritme.app")
test_ref = ref(tests, "RitmeTests", "RitmeTests.xctest")
(schemes / "Ritme.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print("Generated", project)
