# Generate a standard macOS XCTest UI bundle on the ephemeral Xcode host.
require 'xcodeproj'
project = Xcodeproj::Project.new('ProductUpgrade.xcodeproj')
host = project.new_target(:application, 'HarnessHost', :osx, '13.0')
ui = project.new_target(:ui_test_bundle, 'ProductUpgradeUI', :osx, '13.0')
host.add_file_references([project.main_group.new_reference('main.swift')])
ui.add_file_references([project.main_group.new_reference('PublicUpgradeUI.swift')])
ui.add_dependency(host)
[host, ui].each do |target|
  target.build_configurations.each do |cfg|
    cfg.build_settings.merge!({
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.riftlet.qa.#{target.name}",
      'CODE_SIGN_STYLE' => 'Manual', 'CODE_SIGN_IDENTITY' => '-',
      'SWIFT_VERSION' => '5.0', 'MACOSX_DEPLOYMENT_TARGET' => '13.0',
      'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
    })
    cfg.build_settings['TEST_TARGET_NAME'] = host.name if target == ui
  end
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_test_target(ui)
scheme.save_as(project.path, 'PublicUpgrade', true)
