$LOAD_PATH.push(BACKPORT_LIB_DIR)

require 'ci'
require 'travis'
require 'azure'
require 'repo'
require 'branch'

$LOAD_PATH.pop()

class String
    # colorization
    @@is_a_tty = nil
    def colorize(color_code)
        @@is_a_tty = STDOUT.isatty() if @@is_a_tty == nil
        if @@is_a_tty then
            return "\e[#{color_code}m#{self}\e[0m"
        else
            return self
        end
    end

    def red
        colorize(31)
    end

    def green
        colorize(32)
    end

    def brown
        colorize(33)
    end

    def blue
        colorize(34)
    end

    def magenta
        colorize(35)
    end
end

module GitMaintain
    class Common
        ACTION_LIST = [ :list_actions ]
        ACTION_HELP = []
        def self.execAction(opts, action)
            puts GitMaintain::getActionAttr("ACTION_LIST").join("\n")
        end
    end

    ACTION_CLASS = [ Common, Branch, Repo ]
    @@custom_classes = {}
    @@load_class = []
    @@verbose_log = false

    def registerCustom(repo_name, classes)
        raise("Multiple class for repo #{repo_name}") if @@custom_classes[repo_name] != nil
        @@custom_classes[repo_name] = classes
    end
    module_function :registerCustom

    def getClass(default_class, repo_name = File.basename(Dir.pwd()))
        custom = @@custom_classes[repo_name]
        if custom != nil && custom[default_class] != nil then
            log(:DEBUG,"Detected custom #{default_class} class for repo '#{repo_name}'")
            return custom[default_class]
        else
            log(:DEBUG,"Detected NO custom #{default_class} classes for repo '#{repo_name}'")
            return default_class
        end
    end
    module_function :getClass

    def loadClass(default_class, repo_name, *more)
        @@load_class.push(default_class)
        obj = GitMaintain::getClass(default_class, repo_name).new(*more)
        @@load_class.pop()
        return obj
    end
    module_function :loadClass

    # Check that the constructor was called through loadClass
    def checkDirectConstructor(theClass)
        curLoad= @@load_class.last()
        cl = theClass
        while cl != Object
            return if cl == curLoad
            cl = cl.superclass
        end
        raise("Use GitMaintain::loadClass to construct a #{theClass} class")
    end
    module_function :checkDirectConstructor

    def getActionAttr(attr)
        return ACTION_CLASS.map(){|x| x.const_get(attr)}.flatten()
    end
    module_function :getActionAttr

    def setOpts(action, optsParser, opts)
         ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(action) == nil
            if x.singleton_methods().index(:set_opts) != nil then
                x.set_opts(action, optsParser, opts)
            end
            # Try to add repo specific opts
            y = getClass(x)
            if x != y && y.singleton_methods().index(:set_opts) != nil then
                y.set_opts(action, optsParser, opts)
            end
            break
        }
    end
    module_function :setOpts

    def checkOpts(opts)
        ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(opts[:action]) == nil
            next if x.singleton_methods().index(:check_opts) == nil
            x.check_opts(opts)

            # Try to add repo specific opts
            y = getClass(x)
            if x != y && y.singleton_methods().index(:check_opts) != nil then
                y.check_opts(opts)
            end
        }
    end
    module_function :checkOpts

    def execAction(opts, action)
        ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(action) == nil
            x.execAction(opts, action)
            break
        }
    end
    module_function :execAction

    def confirm(opts, msg, ignore_default=false)
        rep = 't'
        while rep != "y" && rep != "n" && rep != '' do
            puts "Do you wish to #{msg} ? (y/N): "
            case (ignore_default == true ? nil : opts[:yn_default])
            when :no
                puts "Auto-replying no due to --no option"
                rep = 'n'
            when :yes
                puts "Auto-replying yes due to --yes option"
                rep = 'y'
            else
                rep = STDIN.gets.chomp()
            end
        end
        return rep
    end
    module_function :confirm

    def checkLog(opts, br1, br2, action_msg)
        puts "Diff between #{br1} and #{br2}"
        puts `git log --format=oneline #{br1} ^#{br2}`
        return "n" if action_msg.to_s() == ""
        rep = confirm(opts, "#{action_msg} this branch")
        return rep
    end
    module_function :checkLog

    def showLog(opts, br1, br2)
        log(:INFO, "Diff between #{br1} and #{br2}")
        puts `git log --format=oneline #{br1} ^#{br2}`
        return "n"
    end
    module_function :showLog

    def _log(lvl, str, out=STDOUT)
        puts("# " + lvl.to_s() + ": " + str)
    end
    module_function :_log

    def log(lvl, str)
        case lvl
        when :DEBUG
            _log("DEBUG".magenta(), str) if ENV["DEBUG"].to_s() != ""
        when :DEBUG_CI
            _log("DEBUG_CI".magenta(), str) if ENV["DEBUG_CI"].to_s() != ""
        when :VERBOSE
            _log("INFO".blue(), str) if @@verbose_log == true
        when :INFO
            _log("INFO".green(), str)
        when :WARNING
            _log("WARNING".brown(), str)
        when :ERROR
            _log("ERROR".red(), str, STDERR)
        else
            _log(lvl, str)
        end
    end
    module_function :log

    def setVerbose(val)
        @@verbose_log = val
    end
    module_function :setVerbose
end
$LOAD_PATH.pop()


# Load all custom classes
$LOAD_PATH.push(BACKPORT_LIB_DIR + "/addons/")
Dir.entries(BACKPORT_LIB_DIR + "/addons/").each(){|entry|
    next if (!File.file?(BACKPORT_LIB_DIR + "/addons/" + entry) || entry !~ /\.rb$/ );
    require entry.sub(/.rb$/, "")
}
$LOAD_PATH.pop()
