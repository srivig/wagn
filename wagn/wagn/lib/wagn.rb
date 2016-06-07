# should be able to move these to more appropriate places
WAGN_GEM_ROOT = File.expand_path('../..', __FILE__)

module Wagn

  class << self    
    def root
      Rails.root
    end
  
    def application
      Rails.application
    end
    
    def config
      application.config
    end
    
    def paths
      application.paths
    end
    
    def gem_root
      WAGN_GEM_ROOT
    end
  end
end
