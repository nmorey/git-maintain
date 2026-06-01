module GitMaintain

    # Base class for all GitMaintain exceptions
    class GitMaintainError < RuntimeError
    end

    # Exception raised when a shell command fails
    class RunError < GitMaintainError
        # Initialize a new RunError
        # @param err_code [Integer] Exit code
        # @param msg [String] Error message
        def initialize(err_code, msg = nil)
            super("Command failed with error code '#{err_code}'")
            @err_code = err_code
            @msg = msg
        end
        # @!attribute [r] err_code
        #   @return [Integer] The exit code of the failed command
        # @!attribute [r] msg
        #   @return [String] Optional error message
        attr_reader :err_code, :msg
    end

    # Exception raised when cherry-pick is aborted by user
    class CPAbort < GitMaintainError
    end

    # Exception raised when cherry-pick of a patch is skipped by user
    class CPSkip < GitMaintainError
        # Initialize a new SCPSkip error
        # @param s [String] Message or patch info
        def initialize(s="")
            super("Skipping patch #{s}")
        end
    end

    # Exception raised when a SHA is not found in the repository
    class ShaNotFoundError < GitMaintainError
        # Initialize a new ShaNotFoundError
        # @param sha [String] The missing SHA
        def initialize(sha)
            super("SHA '#{sha}' was not found in the repository")
        end
    end

    # Exception raised when a required argument is missing
    class MissingArgumentError < GitMaintainError
        # Initialize a new MissingArgumentError
        # @param arg [String] The name of the missing argument
        def initialize(arg)
            super("Missing required argument: #{arg}")
        end
    end

    # Exception raised when an argument is incorrect
    class InvalidArgumentError < GitMaintainError
        # Initialize a new InvalidArgumentError
        # @param msg [String] Description of the invalid argument
        def initialize(arg)
            super("Invalid argument: #{arg}")
        end
    end

    # Exception raised when a file is not found
    class FileNotFoundError < GitMaintainError
        # Initialize a new FileNotFoundError
        # @param path [String] The path to the missing file
        def initialize(path)
            super("File not found: #{path}")
        end
    end

    # Exception raised when a reference is not found in the repository
    class NoRefError < GitMaintainError
        def initialize(ref)
            super("Reference '#{ref}' was not found")
        end
    end

    # Exception raised when a cherry-pick fails
    class CherryPickErrorException < GitMaintainError
        def initialize(str, commit)
            @commit = commit
            super(str)
        end
        attr_reader :commit
    end
end
