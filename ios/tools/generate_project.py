"""Generate the checked-in Xcode project without a third-party project generator."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
objects={}
def ident(key):return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def obj(key,isa,**kw):
 i=ident(key);objects[i]={'isa':isa,**kw};return i
files=[];builds=[]
for path in sorted((ROOT/'DeckReady').glob('*.swift')):
 f=obj(path.name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=path.name,sourceTree='<group>');files.append(f)
 builds.append(obj('build'+path.name,'PBXBuildFile',fileRef=f))
testfile=obj('testfile','PBXFileReference',lastKnownFileType='sourcecode.swift',path='DeckReadyTests.swift',sourceTree='<group>')
testbuild=obj('testbuild','PBXBuildFile',fileRef=testfile)
app=obj('app','PBXFileReference',explicitFileType='wrapper.application',path='DeckReady.app',sourceTree='BUILT_PRODUCTS_DIR')
tests=obj('tests','PBXFileReference',explicitFileType='wrapper.cfbundle',path='DeckReadyTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
sourcegroup=obj('sources','PBXGroup',children=files,path='DeckReady',sourceTree='<group>')
testgroup=obj('testgroup','PBXGroup',children=[testfile],path='DeckReadyTests',sourceTree='<group>')
products=obj('products','PBXGroup',children=[app,tests],name='Products',sourceTree='<group>')
main=obj('main','PBXGroup',children=[sourcegroup,testgroup,products],sourceTree='<group>')
package=obj('zip','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/weichsel/ZIPFoundation.git',requirement={'kind':'exactVersion','version':'0.9.20'})
zipproduct=obj('zipproduct','XCSwiftPackageProductDependency',package=package,productName='ZIPFoundation')
zipbuild=obj('zipbuild','PBXBuildFile',productRef=zipproduct)
sources=obj('sourcephase','PBXSourcesBuildPhase',buildActionMask=2147483647,files=builds,runOnlyForDeploymentPostprocessing=0)
frameworks=obj('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[zipbuild],runOnlyForDeploymentPostprocessing=0)
resources=obj('resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
testsource=obj('testsource','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[testbuild],runOnlyForDeploymentPostprocessing=0)
testframeworks=obj('testframeworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
def configs(key,settings):
 configs=[]
 for name in ['Debug','Release']:
  more={'SWIFT_OPTIMIZATION_LEVEL':'-Onone'} if name=='Debug' else {'SWIFT_COMPILATION_MODE':'wholemodule','SWIFT_OPTIMIZATION_LEVEL':'-O'}
  configs.append(obj(key+name,'XCBuildConfiguration',name=name,buildSettings={**settings,**more}))
 return obj(key+'list','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
projectconfigs=configs('project',{'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','ENABLE_TESTABILITY':'YES'})
appconfigs=configs('target',{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.yodjhill.DeckReady','GENERATE_INFOPLIST_FILE':'YES','INFOPLIST_KEY_CFBundleDisplayName':'DeckReady','INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace':'YES','INFOPLIST_KEY_UIFileSharingEnabled':'YES','INFOPLIST_KEY_UILaunchScreen_Generation':'YES','INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES','TARGETED_DEVICE_FAMILY':'1,2','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'1','CODE_SIGN_STYLE':'Automatic','SWIFT_EMIT_LOC_STRINGS':'YES'})
testconfigs=configs('test',{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.yodjhill.DeckReadyTests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/DeckReady.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/DeckReady','BUNDLE_LOADER':'$(TEST_HOST)','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic'})
target=obj('target','PBXNativeTarget',buildConfigurationList=appconfigs,buildPhases=[sources,frameworks,resources],buildRules=[],dependencies=[],name='DeckReady',productName='DeckReady',productReference=app,productType='com.apple.product-type.application',packageProductDependencies=[zipproduct])
proxy=obj('proxy','PBXContainerItemProxy',containerPortal=ident('project'),proxyType=1,remoteGlobalIDString=target,remoteInfo='DeckReady')
dep=obj('dependency','PBXTargetDependency',target=target,targetProxy=proxy)
testtarget=obj('testtarget','PBXNativeTarget',buildConfigurationList=testconfigs,buildPhases=[testsource,testframeworks],buildRules=[],dependencies=[dep],name='DeckReadyTests',productName='DeckReadyTests',productReference=tests,productType='com.apple.product-type.bundle.unit-test')
project=obj('project','PBXProject',attributes={'LastUpgradeCheck':'1600'},buildConfigurationList=projectconfigs,compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target,testtarget],packageReferences=[package])
def encode(v,depth=0):
 if isinstance(v,dict):return '{\n'+''.join('\t'*(depth+1)+json.dumps(k)+' = '+encode(x,depth+1)+';\n' for k,x in v.items())+'\t'*depth+'}'
 if isinstance(v,list):return '( '+', '.join(encode(x,depth+1) for x in v)+' )'
 if isinstance(v,int):return str(v)
 return json.dumps(v)
(ROOT/'DeckReady.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+encode({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':project})+'\n')
(ROOT/'DeckReady.xcodeproj/xcshareddata/xcschemes/DeckReady.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DeckReady.app" BlueprintName="DeckReady" ReferencedContainer="container:DeckReady.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="DeckReadyTests.xctest" BlueprintName="DeckReadyTests" ReferencedContainer="container:DeckReady.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="DeckReady.app" BlueprintName="DeckReady" ReferencedContainer="container:DeckReady.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated project and shared scheme')
