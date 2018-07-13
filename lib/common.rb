BACKPORT_LIB_DIR = File.dirname(__FILE__)
$LOAD_PATH.push(BACKPORT_LIB_DIR)

require 'travis'
require 'repo'
require 'branch'

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

    def registerCustom(repo_name, classes)
        raise("Multiple class for repo #{repo_name}") if @@custom_classes[repo_name] != nil
        @@custom_classes[repo_name] = classes
    end
    module_function :registerCustom

    def getCustom(repo_name)
        return @@custom_classes[repo_name]
    end
    module_function :getCustom

    def loadClass(default_class, repo_name, *more)
        custom = @@custom_classes[repo_name]
        if custom != nil && custom[default_class] != nil then
            puts "# Detected custom #{default_class} class for repo '#{repo_name}'" if ENV['DEBUG'] == "1"
            return custom[default_class].new(*more)
        else
            puts "# Detected NO custom #{default_class} classes for repo '#{repo_name}'" if ENV['DEBUG'] == "1"
            return default_class.new(*more)
        end
    end
    module_function :loadClass

    # Check that the constructor was called through loadClass
    def checkDirectConstructor(theClass)
        # Look for the "new" in the calling tree
        depth = 1
        while caller_locations(depth, 1)[0].label != "new"
            depth +=1
        end
        # The function that called the constructer is just one step below
        raise("Use GitMaintain::loadClass to construct a #{theClass} class") if
                caller_locations(depth + 1, 1)[0].label != "loadClass"
    end
    module_function :checkDirectConstructor

    def getActionAttr(attr)
        return ACTION_CLASS.map(){|x| x.const_get(attr)}.flatten()
    end
    module_function :getActionAttr

    def setOpts(action, optsParser, opts)
         ACTION_CLASS.each(){|x|
            next if x::ACTION_LIST.index(action) == nil
            next if x.singleton_methods().index(:set_opts) == nil
            x.set_opts(action, optsParser, opts)
            break
        }
    end
    module_function :setOpts

    def checkOpts(opts)
        ACTION_CLASS.each(){|x|
            next if x.singleton_methods().index(:check_opts) == nil
            x.check_opts(opts)
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

    def confirm(opts, msg)
        rep = 't'
        while rep != "y" && rep != "n" && rep != '' do
            puts "Do you wish to #{msg} ? (y/N): "
            if opts[:no] == true then
                puts "Auto-replying bo due to --no option"
                rep = 'n'
            else
                rep = STDIN.gets.chomp()
            end
        end
        return rep
    end
    module_function :confirm

    def checkLog(opts, br1, br2, action_msg)
        puts "Diff between #{br1} and #{br2}"
        puts `git shortlog #{br1} ^#{br2}`
        return "n" if action_msg.to_s() == ""
        rep = confirm(opts, "#{action_msg} this branch")
        return rep
    end
    module_function :checkLog

end
$LOAD_PATH.pop()


# Load all custom classes
$LOAD_PATH.push(BACKPORT_LIB_DIR + "/addons/")
Dir.entries(BACKPORT_LIB_DIR + "/addons/").each(){|entry|
    next if (!File.file?(BACKPORT_LIB_DIR + "/addons/" + entry) || entry !~ /\.rb$/ );
    require entry.sub(/.rb$/, "")
}
$LOAD_PATH.pop()
