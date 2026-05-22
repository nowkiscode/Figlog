require 'xcodeproj'
project_path = 'Figlog.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  if target.name == 'Figlog'
    target.build_configurations.each do |config|
      config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Figlog/Figlog.entitlements'
    end
  end
end

project.save
