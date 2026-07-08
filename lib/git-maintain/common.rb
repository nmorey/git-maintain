require 'cli_class_tool'

# Main module for git-maintain repository maintenance tool.
module GitMaintain
    extend CLIClassTool::Utils
    # Provide module-level log() for use from class methods (e.g. self.check_opts)
    extend CLIClassTool::Logger

    # Base class for git-maintain components providing generic logging and CLI utility helpers.
    class Common < CLIClassTool::Common
        public :log

        # Log an error message and raise a GitMaintainError.
        #
        # @param msg [String] Error message
        # @raise [GitMaintainError] Always raised with the given message
        def crit(msg)
            log(:ERROR, msg)
            raise GitMaintainError.new(msg)
        end

    end

    # Internal registry for custom repo-specific adapters.
    @@custom_classes = {}

    # Internal cached repo path and name
    @@repo_infos = nil

    # Register custom classes (Repo, Branch, CI) for a specific repository name.
    #
    # @param repo_name [String] Name of the repository (e.g. 'rdma-core')
    # @param classes [Hash] Hash mapping default classes (e.g. Repo) to custom subclasses (e.g. RDMACoreRepo)
    # @raise [GitMaintainError] If custom classes are already registered for this repository
    def registerCustom(repo_name, classes)
        raise GitMaintainError.new("Multiple class for repo #{repo_name}") if @@custom_classes[repo_name] != nil
        classes[:name] = repo_name if classes[:name] == nil
        @@custom_classes[repo_name] = classes
    end
    module_function :registerCustom

    def getRepoInfos()
        return @@repo_infos if @@repo_infos != nil

        dir = File.realdirpath(".")
        begin
            repo_path = Common::run(dir, "git rev-parse  --show-toplevel 2> /dev/null")
        rescue RunError
            raise NotARepoError.new(dir)
        end
        return @@repo_infos = [repo_path, File.basename(repo_path)]
    end
    module_function :getRepoInfos

    # Retrieve the registered custom subclass for a given default class and repository name.
    # Returns the default_class if no custom class is registered.
    #
    # @param default_class [Class] Default class to resolve (e.g. Repo)
    # @param repo_name [String] Repository name to search for
    # @return [Class] The resolved class (either the custom subclass or the default_class)
    def getExtendedClass(default_class, repo_name=nil)
        begin
            (_repo_path, repo_name) = getRepoInfos() if repo_name == nil
            custom = @@custom_classes[repo_name]
            if custom != nil && custom[default_class] != nil then
                return custom[default_class]
            else
                return default_class
            end
        rescue NotARepoError
            return default_class
        end
    end
    module_function :getExtendedClass

    # Retrieve all registered custom classes.
    #
    # @return [Hash] Registry of custom classes
    def getCustomClasses()
        return @@custom_classes
    end
    module_function :getCustomClasses

    # Set whether verbose log is enabled.
    #
    # @param val [Boolean] True to enable verbose logs
    def setVerbose(val)
        self.verbose_log = val
    end
    module_function :setVerbose

end

require_relative 'ci'
require_relative 'travis'
require_relative 'azure'
require_relative 'repo'
require_relative 'branch'

# Re-open the module to declare registry functions and load addons.
module GitMaintain
    # Pre-declaration
    class BranchIterator < Common; end

    # Action classes supported by git-maintain CLI.
    ACTION_CLASS = [ Common, BranchIterator, Repo ]

    # Load all custom classes from the default addons directory
    loadAddons(File.expand_path('addons', __dir__))

    # Load any eventual user custom directory if specified
    if ENV["GIT_MAINTAIN_ADDON_DIR"].to_s != ""
        loadAddons(ENV["GIT_MAINTAIN_ADDON_DIR"].to_s)
    end
end

require_relative 'branch_iterator'
