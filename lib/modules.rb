module Reputation
	
	
	module Utils
		@@mutex = Mutex.new

		def self.reputation(options={})
			begin
			  unless (!options.empty? &&
					  (options.keys - [:action, :type, :id, :me, :you, :calculate, :undo, :vid]).empty? &&
					  [:create, :destroy, :update, :up, :down].include?(options[:action].to_sym) && 
					  [:relationship, :issue, :suggestion, :reference, :comment].include?(options[:type].to_sym) &&
					  [true, false].include?(options[:undo]) &&
						[true, false].include?(options[:calculate])
					  )
				  raise ArgumentError, 'Missing or invalid argument :action :type :calculate'
			  end
			  
			  score = [0,0]
			  ids = []


			  case [options[:action],options[:type]]
				  when [:create, :relationship]
					  raise ArgumentError, "Missing or invalid argument :id :me" unless ((!options[:id].nil? && options[:id].integer?) && 
																																								(!options[:me].nil? && options[:me].integer?))

						degree = 3
					  return false unless !(v = Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Relationship', options[:id]]).first).nil? || !(v = Relationship.find(options[:id]))
					  if v.class.to_s.eql?("Version")
							relationship = v.get_object
						elsif v.class.to_s.eql?("Relationship")
							relationship = v
						end
					  [relationship.issue_id, relationship.cause_id].each do |issue_id|
						  return false unless !(v = Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Issue', issue_id]).first).nil? || !(v = Issue.find(issue_id))
						  if v.class.to_s.eql?("Version") && (user_id = v.get_object.user_id) == options[:me]
							  degree -= 1
							elsif v.class.to_s.eql?("Issue") && (user_id = v.user_id) == options[:me]
								degree -= 1
						  else
							  ids << user_id
						  end
					  end

					  case degree
						  when 1 then score = [1,0] #both issues are yours
						  when 2 then score = [3,1] #one of them is yours
						  when 3 then score = [6,2] #none of them is yours
					  end

				  when [:destroy, :relationship]
					  raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:id].nil? && options[:id].integer?) && 
																																										(!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?))
					  ids << options[:you]
						score = [-2,0]

				  when [:create, :issue]
					  raise ArgumentError, "Missing or invalid argument :me" unless (!options[:me].nil? && options[:me].integer?)
					  score = [1,0]

				  when [:destroy, :issue]
					  raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?) && 
																																										(!options[:id].nil? && options[:id].integer?))
					  ids << options[:you]
						score = [-1,0]			

				  when [:create, :reference]
					  raise ArgumentError, "Missing or invalid argument :id :me" unless ((!options[:id].nil? && options[:id].integer?) && 
																																								(!options[:me].nil? && options[:me].integer?))

						degree = 2
					  return false unless !(v = Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Reference', options[:id]]).first).nil? 
					  relationship_id = v.get_object.relationship_id
					  return false unless !(v = Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Relationship', relationship_id]).first).nil?					
					  (user_id = v.get_object.user_id) == options[:me] ? degree -= 1 : ids << user_id

					  case degree
						  when 1 then score = [1,0] #ref on a your rel
						  when 2 then score = [3,2] #ref on other's rel
					  end

				  when [:destroy, :reference]
					  raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:id].nil? && options[:id].integer?) && 
																																										(!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?))					  
						ids << options[:you]
						score = [0,0]


				  when [:up, :relationship]
					  raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:id].nil? && options[:id].integer?) && 
																																										(!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?))


				  when [:down, :relationship]
					  raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:id].nil? && options[:id].integer?) && 
																																										(!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?))

					when [:update, :suggestion]
						raise ArgumentError, "Missing or invalid argument :id :me" unless ((!options[:id].nil? && options[:id].integer?) && 
																																								(!options[:me].nil? && options[:me].integer?))
						return false unless !(v = Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Suggestion', options[:id]]).first).nil?
						if v.reify.status.eql?('N') && v.get_object.status.eql?('D') #reject only
							score = [1,0]
						end

					when [:create, :comment]
						raise ArgumentError, "Missing or invalid argument :id :me" unless ((!options[:id].nil? && options[:id].integer?) && 
																																								(!options[:me].nil? && options[:me].integer?))
						score = [0,0]

					when [:destroy, :comment]
						raise ArgumentError, "Missing or invalid argument :id :me :you" unless ((!options[:id].nil? && options[:id].integer?) && 
																																										(!options[:me].nil? && options[:me].integer?) && 
																																										(!options[:you].nil? && options[:you].integer?))
						score = [0,0]
						ids << options[:you]

			  end
				  
				if options[:undo]
					raise ArgumentError, "Missing or invalid argument :vid" unless (!options[:vid].nil? && options[:vid].integer?) 
					((Version.find(options[:vid]).index % 2) == 0 ) ? score = [-score[0],-score[1]] : score = score #since versions are recorded only on "create" and "destroy" events, even indexed versions (compared to its sibling_versions) are reverts.
				end

			  if options[:calculate]
				  @@mutex.synchronize{
					  mine = ((me = User.find(options[:me])).reputation + score[0])
					  (mine < 1) ? me.update_attributes(:reputation=>1) : me.update_attributes(:reputation=>mine)
				  
					  ids.each do |id|
						  yours = ((you = User.find(id)).reputation + score[1])
					  	(yours < 1) ? you.update_attributes(:reputation=>1) : you.update_attributes(:reputation=>yours)
					  end
					  return true
				  }
			  else
				  return score
			  end
		  rescue Exception => exception
				case exception.class
					when ArgumentError.class #ignore
					else
						ReportMailer.notify(exception).deliver #just for rep system
				end 
		    return false
		  end
		end

		def self.recalculate
			User.all.each do |user|
				user.update_attributes(:reputation=>1)
			end
			Version.all.each do |version|
				if version.reverted_from.nil?
					Reputation::Utils.reputation(:action=>version.event.downcase.to_sym, \
																					:type=>version.item_type.downcase.to_sym, \
																					:id=>version.item_id.to_i, \
																					:me=>version.whodunnit.to_i, \
																					:you=>(version.get_object.attributes.has_key?("user_id") ? version.get_object.user_id.to_i : nil), \
																					:undo=>false, :calculate=>true)
				end
				if version.next
					Reputation::Utils.reputation(:action=>version.sibling_versions.first.event.downcase.to_sym, \
																					:type=>version.sibling_versions.first.item_type.downcase.to_sym, \
																					:id=>version.sibling_versions.first.item_id.to_i, \
																					:me=>version.sibling_versions.first.whodunnit.to_i, \
																					:you=>(version.get_object.attributes.has_key?("user_id") ? version.get_object.user_id.to_i : nil), \
																					:vid=>version.id, \
																					:undo=>true, \
																					:calculate=>true)
				end			
			end
		end

	end

	module ClassMethods
	end

	module InstanceMethods
	end
end


module Maintenance
	
	module Utils
		
		#help 'cure' inconsistent database between versioning deployment & repmanagement deployment
		#run once only ---- DONE
		def self.make_consistent
			Issue.all.each do |issue|
				if Version.find(:all, :conditions=>["item_type=? AND item_id=?", 'Issue', issue.id]).empty?
					Version.create(:item_type=>'Issue', :item_id=>issue.id, :event=>'create', :whodunnit=>issue.user_id, :object=>nil, :created_at=>issue.updated_at, :reverted_from=>nil)

				end					
			end

			Version.find(:all,:conditions=>["item_type=?", 'Relationship']).each do |version|
				if version.event.eql?('create')
					if Relationship.exists?(version.item_id)
						Relationship.paper_trail_off
						Relationship.find(version.item_id).update_attributes(:user_id=>version.whodunnit)
						Relationship.paper_trail_on
					else
						Version.find(:all, :conditions=>['item_type=? AND item_id=? AND event != ?', 'Relationship', version.item_id, 'create']).each do |v|
							!(o = v.object).include?('user_id') ? v.update_attributes(:object=>o+"user_id: #{version.whodunnit.to_s}\n") : v.update_attributes(:object=>o.gsub(/user_id\:/,"user_id: #{version.whodunnit.to_s}"))
						end
					end
				end
			end
		end
	
		#add 'relationship_type' to object string of each version that doesn't have relationship_type
		#run once only
		def self.make_consistent1
			Version.find(:all, :conditions=>["item_type=?", "Relationship"]).each do |version|
				if version.object
					if !version.object.include?("relationship_type")
						o = version.object
						version.update_attributes(:object=>o+"relationship_type: \n")
					end
				end
			end
		end

		def self.make_consistent2
      Issue.all.each do |issue|
        if issue.suggestions.count == 0
          arr = Suggestion.new.get_suggestions(issue.wiki_url, issue.id)
          arr.each do |s|
            Suggestion.create(s)
          end
        end
      end
    end


	end
end

