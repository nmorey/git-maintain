$LOAD_PATH.push(File.dirname(__FILE__))

require 'travis'
require 'repo'
require 'branch'

module Backport
    ACTION_CLASS = [ Branch, Repo ]

    def getActionAttr(attr)
        return ACTION_CLASS.map(){|x| x.const_get(attr)}.flatten()
    end
    module_function :getActionAttr

    def checkOpts(opts)
        ACTION_CLASS.each(){|x|
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
