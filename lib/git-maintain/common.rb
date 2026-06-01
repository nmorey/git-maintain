require 'cli_class_tool'

GIT_MAINTAIN_LIB_DIR = File.expand_path('..', __dir__) unless defined?(GIT_MAINTAIN_LIB_DIR)

module GitMaintain
    extend CLIClassTool::Utils

    class Common < CLIClassTool::Common
        public :log

        def crit(msg)
            log(:ERROR, msg)
            raise msg
        end

    end
end

require_relative 'ci'
require_relative 'travis'
require_relative 'azure'
require_relative 'repo'
require_relative 'branch'

module GitMaintain
    ACTION_CLASS = [ Common, Branch, Repo ]
    @@custom_classes = {}
    @helper = Common.new

    def registerCustom(repo_name, classes)
        raise("Multiple class for repo #{repo_name}") if @@custom_classes[repo_name] != nil
        classes[:name] = repo_name if classes[:name] == nil
        @@custom_classes[repo_name] = classes
    end
    module_function :registerCustom

    def getExtendedClass(default_class, repo_name = File.basename(Dir.pwd()))
        custom = @@custom_classes[repo_name]
        if custom != nil && custom[default_class] != nil then
            return custom[default_class]
        else
            return default_class
        end
    end
    module_function :getExtendedClass

    def getCustomClasses()
        return @@custom_classes
    end
    module_function :getCustomClasses

    def log(lvl, str)
        @helper.log(lvl, str)
    end
    module_function :log

    def setVerbose(val)
        self.verbose_log = val
    end
    module_function :setVerbose

    # Load all custom classes from the default addons directory
    loadAddons(File.expand_path('addons', __dir__))

    # Load any eventual user custom directory if specified
    if ENV["GIT_MAINTAIN_ADDON_DIR"].to_s != ""
        loadAddons(ENV["GIT_MAINTAIN_ADDON_DIR"].to_s)
    end
end

