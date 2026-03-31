# frozen_string_literal: true

module Demo
  module Colors
    GREEN = "\e[32m"
    RED = "\e[31m"
    YELLOW = "\e[33m"
    CYAN = "\e[36m"
    DIM = "\e[2m"
    BOLD = "\e[1m"
    RESET = "\e[0m"

    module_function

    def green(msg)  "#{GREEN}#{msg}#{RESET}" end
    def red(msg)    "#{RED}#{msg}#{RESET}" end
    def yellow(msg) "#{YELLOW}#{msg}#{RESET}" end
    def cyan(msg)   "#{CYAN}#{msg}#{RESET}" end
    def dim(msg)    "#{DIM}#{msg}#{RESET}" end
    def bold(msg)   "#{BOLD}#{msg}#{RESET}" end
  end
end
