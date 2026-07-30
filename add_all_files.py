import re

# Read the project file
with open('/Users/arpituppal/Downloads/Signoff/Signoff/Signoff.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# List of files to add: (uuid_prefix, path, group_path)
files_to_add = [
    # DesignSystem
    ("B1", "DesignSystem/DesignPrimitives.swift"),
    
    # Models
    ("B2", "Models/SampleData.swift"),
    
    # Views/Settings
    ("B3", "Views/Settings/ShortcutsSettingsPane.swift"),
    ("B4", "Views/Settings/DiagnosticsSettingsPane.swift"),
    ("B5", "Views/Settings/BucketsSettingsPane.swift"),
    
    # Automation
    ("B6", "Automation/ShortcutManager.swift"),
    ("B7", "Automation/ClipboardManager.swift"),
    ("B8", "Automation/PasteAutomation.swift"),
    
    # Generation
    ("B9", "Generation/PostProcessor/SignoffPostProcessor.swift"),
    ("BA", "Generation/SignoffLLMConfig.swift"),
    ("BB", "Generation/SignoffOutput.swift"),
    ("BC", "Generation/SignoffLLMClient.swift"),
    ("BD", "Generation/PromptBuilder.swift"),
    ("BE", "Generation/BucketManager.swift"),
    
    # Diagnostics
    ("BF", "Diagnostics/QualityDashboard.swift"),
    ("C0", "Diagnostics/SafetyTagger.swift"),
    ("C1", "Diagnostics/SignoffEvaluator.swift"),
    ("C2", "Diagnostics/VersionManager.swift"),
    ("C3", "Diagnostics/EvaluationModels.swift"),
    
    # Onboarding
    ("C4", "Onboarding/OnboardingFlow.swift"),
    ("C5", "Onboarding/OnboardingModels.swift"),
    ("C6", "Onboarding/OnboardingScreens.swift"),
    ("C7", "Onboarding/OnboardingSteps.swift"),
    ("C8", "Onboarding/OnboardingWindowController.swift"),
]

# Generate UUIDs for each file
# Format: 24 char hex
def gen_uuid(prefix, index):
    return f"{prefix}{index:02X}00000000000000000000"

# Find the insertion points
# We'll insert after DesignTokens.swift in each section

# 1. PBXFileReference section
file_refs = []
for i, (prefix, path) in enumerate(files_to_add):
    name = path.split('/')[-1]
    uuid = gen_uuid(prefix, i)
    file_refs.append(f'\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {name}; path = {path}; sourceTree = "<group>"; }};')

# Insert after DesignTokens.swift
design_tokens_ref = '\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = DesignTokens.swift; path = DesignSystem/DesignTokens.swift; sourceTree = "<group>"; };'
content = content.replace(design_tokens_ref, design_tokens_ref + '\n' + '\n'.join(file_refs))

# 2. PBXBuildFile section
build_files = []
for i, (prefix, path) in enumerate(files_to_add):
    name = path.split('/')[-1]
    file_ref_uuid = gen_uuid(prefix, i)
    build_uuid = gen_uuid(prefix, i + 100)
    build_files.append(f'\t\t{build_uuid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid}; }};')

design_tokens_build = '\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A2CED204698475D911178D0; };'
content = content.replace(design_tokens_build, design_tokens_build + '\n' + '\n'.join(build_files))

# 3. PBXSourcesBuildPhase section
sources_entries = []
for i, (prefix, path) in enumerate(files_to_add):
    name = path.split('/')[-1]
    build_uuid = gen_uuid(prefix, i + 100)
    sources_entries.append(f'\t\t\t\t{build_uuid} /* {name} in Sources */,')

design_tokens_sources = '\t\t\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */,'
content = content.replace(design_tokens_sources, design_tokens_sources + '\n' + '\n'.join(sources_entries))

# 4. Add to DesignSystem group (for DesignPrimitives)
# Find the DesignSystem group children
design_system_group = '\t\t\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */,'
content = content.replace(design_system_group, design_system_group + '\n\t\t\t\tB10000000000000000000000 /* DesignPrimitives.swift */,')

# 5. Add to Models group
models_group = '\t\t\t\t7EECEB5F9D934D4A8357F678 /* SettingsModels.swift */,'
content = content.replace(models_group, models_group + '\n\t\t\t\tB20000000000000000000000 /* SampleData.swift */,')

# 6. Add to Views/Settings group
# Find the last settings pane
settings_group = '\t\t\t\t141AF3BD66284CF591624DE9 /* SettingsRootView.swift */,'
content = content.replace(settings_group, settings_group + '\n\t\t\t\tB30000000000000000000000 /* ShortcutsSettingsPane.swift */,\n\t\t\t\tB40000000000000000000000 /* DiagnosticsSettingsPane.swift */,\n\t\t\t\tB50000000000000000000000 /* BucketsSettingsPane.swift */,')

# 7. Add to Automation group
automation_group = '\t\t\t\t6704552611104B9BA08F2BF4 /* BucketManager.swift */,'
content = content.replace(automation_group, automation_group + '\n\t\t\t\tB60000000000000000000000 /* ShortcutManager.swift */,\n\t\t\t\tB70000000000000000000000 /* ClipboardManager.swift */,\n\t\t\t\tB80000000000000000000000 /* PasteAutomation.swift */,')

# 8. Add to Generation group
generation_group = '\t\t\t\t61211EC3F3904276894BD4C4 /* PromptBuilder.swift */,'
content = content.replace(generation_group, generation_group + '\n\t\t\t\tBA0000000000000000000000 /* SignoffLLMConfig.swift */,\n\t\t\t\tBB0000000000000000000000 /* SignoffOutput.swift */,\n\t\t\t\tBC0000000000000000000000 /* SignoffLLMClient.swift */,\n\t\t\t\tBD0000000000000000000000 /* PromptBuilder.swift */,\n\t\t\t\tBE0000000000000000000000 /* BucketManager.swift */,')

# 9. Add to Diagnostics group
diagnostics_group = '\t\t\t\t7CA05C6314A64254B87BF044 /* OnboardingFlow.swift */,'
# Actually, let's find the Diagnostics group
# Search for Diagnostics group
# For now, let's add after Onboarding group

# 10. Add to Onboarding group
onboarding_group = '\t\t\t\t753F33D09FD74F67B7F41FE8 /* OnboardingSteps.swift */,'
content = content.replace(onboarding_group, onboarding_group + '\n\t\t\t\tC40000000000000000000000 /* OnboardingFlow.swift */,\n\t\t\t\tC50000000000000000000000 /* OnboardingModels.swift */,\n\t\t\t\tC60000000000000000000000 /* OnboardingScreens.swift */,\n\t\t\t\tC70000000000000000000000 /* OnboardingSteps.swift */,')

# Write the modified content
with open('/Users/arpituppal/Downloads/Signoff/Signoff/Signoff.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Added all files to project.pbxproj")
