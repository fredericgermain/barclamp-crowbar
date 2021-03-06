# Copyright 2013, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Snapshot < ActiveRecord::Base

  STATUS_CREATED        = 1  # Not applied, just created
  STATUS_QUEUED      = 2  # Attempt at commit, but is queued
  STATUS_COMMITTING  = 3  # Attempt at commit is in progress
  STATUS_FAILED      = 4  # Attempted commit failed
  STATUS_APPLIED     = 5  # Attempted commit succeeded

  ROLE_ORDER         = "'roles'.'order', 'roles'.'run_order'"
  
  attr_accessible :id, :name, :description, :order, :status, :failed_reason, :element_order
  attr_accessible :deployement_id, :barclamp_id, :jig_event_id
  
  belongs_to      :barclamp
  belongs_to      :deployment,        :inverse_of => :snapshot

  has_many        :roles,             :dependent => :destroy, :order => ROLE_ORDER
  has_many        :nodes,             :through => :roles
  has_many        :private_roles,     :class_name => "Role", :conditions=>'run_order<0', :order => ROLE_ORDER
  has_many        :public_roles,      :class_name => "Role", :conditions=>'run_order>=0', :order => ROLE_ORDER

  has_many        :attribs,           :through => :roles
  has_many        :attrib_types,      :through => :attribs
  
  has_many        :jig_events
  
  def active?
    deployment.active_snapshot_id == self.id
  end

  def committed? 
    deployment.committed_snapshot_id == self.id
  end
  
  def proposed?
    deployment.proposed_snapshot_id == self.id
  end
 
  # Add a role to a snapshot by creating the needed Role
  # Returns a Role
  def add_role(role_name)
    r = Role.find_or_create_by_name_and_snapshot_id :name=>role_name, :snapshot_id => self.id
    r.save! unless r.id
    r
  end

  def private_role
    add_role('private')
  end

  # Add attrib to snapshot
  # assume first public role (fall back to private role) if none given
  def add_attrib(attrib_type, role_name=nil)
    desc = I18n.t 'added', :scope => 'model.role', :name=>self.name
    unless role_name
      role = public_roles.first || private_roles.first || private_role
    else
      role = Role.find_or_create_by_name_and_snapshot_id :name => role_name,
                                                         :snapshot_id => self.id,
                                                         :description => desc
    end
    role.add_attrib attrib_type, nil, self.name
  end

  # determines the role run order using the imported element_order
  # return is a nested array of roles
  def role_order
    ro = []
    source = ActiveSupport::JSON.decode(self.element_order)
    if source
      source.each do |parent|
        children = []
        parent.each do |role|
          children << self.add_role(role) if role
        end
        ro << children
      end
    end
    ro
  end

  ##
  # Clone this snapshot
  # optionally, change parent too (you do NOT have parents for templates)
  def deep_clone(parent_deployment=nil, name=nil, with_nodes=true)

    new_snap = self.dup
    new_snap.deployment_id = parent_deployment.id if parent_deployment
    new_snap.name = name || "#{self.name}_#{self.id}"
    new_snap.status = STATUS_CREATED
    new_snap.failed_reason = nil
    new_snap.save

    # clone the roles
    roles.each { |ri| ri.deep_clone(new_snap, with_nodes) }

    new_snap
  end

  def method_missing(m,*args,&block)
    if m.to_s =~ /(.*)_role$/
      r = Role.find_by_name_and_snapshot_id $1, self.id
      # temporary while we depricate the node role
      return r
    else
      super m,*args,&block
    end
  end

end
