# frozen_string_literal: true

module DiscourseSuggestedEdits
  class Engine < ::Rails::Engine
    engine_name DiscourseSuggestedEdits::PLUGIN_NAME
    isolate_namespace DiscourseSuggestedEdits
    config.autoload_paths << File.join(config.root, "lib")
  end
end
