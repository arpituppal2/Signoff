import re
import uuid

# Read the project file
with open('/Users/arpituppal/Downloads/Signoff/Signoff/Signoff.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Generate UUIDs (using similar format)
# PBXFileReference UUID
file_ref_uuid = "AA2CED204698475D911178D1"
# PBXBuildFile UUID
build_file_uuid = "AA3CB8CC8D004FDFB91FFDA4"

# 1. Add to PBXFileReference section (after DesignTokens.swift)
file_ref_entry = f'''\t\t{file_ref_uuid} /* DesignPrimitives.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = DesignPrimitives.swift; path = DesignSystem/DesignPrimitives.swift; sourceTree = "<group>"; }};'''

content = content.replace(
    '\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = DesignTokens.swift; path = DesignSystem/DesignTokens.swift; sourceTree = "<group>"; };',
    f'\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = DesignTokens.swift; path = DesignSystem/DesignTokens.swift; sourceTree = "<group>"; }};\n{file_ref_entry}'
)

# 2. Add to PBXBuildFile section (after DesignTokens.swift)
build_file_entry = f'''\t\t{build_file_uuid} /* DesignPrimitives.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid}; }};'''

content = content.replace(
    '\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = 5A2CED204698475D911178D0; };',
    f'\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */ = {{isa = PBXBuildFile; fileRef = 5A2CED204698475D911178D0; }};\n{build_file_entry}'
)

# 3. Add to PBXSourcesBuildPhase section (after DesignTokens.swift)
sources_entry = f'\t\t\t\t{build_file_uuid} /* DesignPrimitives.swift in Sources */,'

content = content.replace(
    '\t\t\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */,',
    f'\t\t\t\tA63CB8CC8D004FDFB91FFDA3 /* DesignTokens.swift in Sources */,\n{sources_entry}'
)

# Also need to add to the DesignSystem group
# Find the DesignSystem group and add the file reference
group_entry = f'\t\t\t\t{file_ref_uuid} /* DesignPrimitives.swift */,'

content = content.replace(
    '\t\t\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */,',
    f'\t\t\t\t5A2CED204698475D911178D0 /* DesignTokens.swift */,\n{group_entry}'
)

# Write the modified content
with open('/Users/arpituppal/Downloads/Signoff/Signoff/Signoff.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print("Added DesignPrimitives.swift to project.pbxproj")
