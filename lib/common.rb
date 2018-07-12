BACKPORT_LIB_DIR = File.dirname(__FILE__)
$LOAD_PATH.push(BACKPORT_LIB_DIR)

require 'travis'
require 'repo'
require 'branch'

module Backport
    ACTION_CLASS = [ Branch, Repo ]
    @@custom_classes = {}

    def registerCustom(repo_name, repoClass, branchClass)
        raise("Multiple class for repo #{repo_name}") if @@custom_classes[repo_name] != nil
        @@custom_classes[repo_name] = { :repo => repoClass, :branch => branchClass }
    end
    module_function :registerCustom

    def getCustom(repo_name)
        return @@custom_classes[repo_name]
    end
    module_function :getCustom

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
