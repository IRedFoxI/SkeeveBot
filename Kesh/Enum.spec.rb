require 'rspec'
require './Enum.class'

AdminLevel = Enum.new(:None, :Admin, :SuperUser)

describe AdminLevel do

	describe '::parse' do
		it 'should return nil when passed nil' do
			AdminLevel::parse(nil).nil?.should
		end

		it 'should return nil when passed 0' do
			AdminLevel::parse(0).nil?.should
		end

		it 'should return nil when passed "Overlord"' do
			AdminLevel::parse('Overlord').nil?.should
		end

		it 'should return ::None when passed "None"' do
			AdminLevel::parse('None').should == AdminLevel::None
		end

		it 'should return ::None when passed "none"' do
			AdminLevel::parse('none').should == AdminLevel::None
		end

		it 'should return ::Admin when passed "Admin"' do
			AdminLevel::parse('Admin').should == AdminLevel::Admin
		end

		it 'should return ::Admin when passed "admin"' do
			AdminLevel::parse('admin').should == AdminLevel::Admin
		end

		it 'should return ::SuperUser when passed "SuperUser"' do
			AdminLevel::parse('SuperUser').should == AdminLevel::SuperUser
		end

		it 'should return ::SuperUser when passed "superuser"' do
			AdminLevel::parse('superuser').should == AdminLevel::SuperUser
		end
	end

	describe '#to_s' do
		it 'should return "None" for ::None' do
			AdminLevel::None.to_s.should == 'None'
		end

		it 'should return "Admin" for ::Admin' do
			AdminLevel::Admin.to_s.should == 'Admin'
		end

		it 'should return "SuperUser" for ::SuperUser' do
			AdminLevel::SuperUser.to_s.should == 'SuperUser'
		end
	end

	describe '#inspect' do
		it 'should return "None (0)" for ::None' do
			AdminLevel::None.inspect.should == 'None (0)'
		end

		it 'should return "Admin (1)" for ::Admin' do
			AdminLevel::Admin.inspect.should == 'Admin (1)'
		end

		it 'should return "SuperUser (2)" for ::SuperUser' do
			AdminLevel::SuperUser.inspect.should == 'SuperUser (2)'
		end
	end

	describe '::None' do
		it 'should exist' do
			AdminLevel::None.should
		end

		it 'should be constant' do
			AdminLevel.const_defined?(:None).should
		end

		it 'should be equal to ::None' do
			AdminLevel::None.should == AdminLevel::None
		end

		it 'should not be equal to ::Admin' do
			AdminLevel::None.should_not == AdminLevel::Admin
		end

		it 'should not be equal to ::SuperUser' do
			AdminLevel::None.should_not == AdminLevel::SuperUser
		end

		it 'should be equal to "None"' do
			AdminLevel::None.should == 'None'
		end

		it 'should not be equal to "Admin"' do
			AdminLevel::None.should_not == 'Admin'
		end

		it 'should not be equal to "SuperUser"' do
			AdminLevel::None.should_not == 'SuperUser'
		end

		it 'should be equal to 0' do
			AdminLevel::None.should == 0
		end

		it 'should not be equal to 1' do
			AdminLevel::None.should_not == 1
		end

		it 'should not be equal to 2' do
			AdminLevel::None.should_not == 2
		end
	end

	describe '::Admin' do
		it 'should exist' do
			AdminLevel::Admin.should
		end

		it 'should be constant' do
			AdminLevel.const_defined?(:Admin).should
		end

		it 'should not be equal to ::None' do
			AdminLevel::Admin.should_not == AdminLevel::None
		end

		it 'should be equal to ::Admin' do
			AdminLevel::Admin.should == AdminLevel::Admin
		end

		it 'should not be equal to ::SuperUser' do
			AdminLevel::Admin.should_not == AdminLevel::SuperUser
		end

		it 'should not be equal to "None"' do
			AdminLevel::Admin.should_not == 'None'
		end

		it 'should be equal to "Admin"' do
			AdminLevel::Admin.should == 'Admin'
		end

		it 'should not be equal to "SuperUser"' do
			AdminLevel::Admin.should_not == 'SuperUser'
		end

		it 'should not be equal to 0' do
			AdminLevel::Admin.should_not == 0
		end

		it 'should be equal to 1' do
			AdminLevel::Admin.should == 1
		end

		it 'should not be equal to 2' do
			AdminLevel::Admin.should_not == 2
		end
	end

	describe '::SuperUser' do
		it 'should exist' do
			AdminLevel::SuperUser.should
		end

		it 'should be constant' do
			AdminLevel.const_defined?(:SuperUser).should
		end

		it 'should not be equal to ::None' do
			AdminLevel::SuperUser.should_not == AdminLevel::None
		end

		it 'should not be equal to ::Admin' do
			AdminLevel::SuperUser.should_not == AdminLevel::Admin
		end

		it 'should be equal to ::SuperUser' do
			AdminLevel::SuperUser.should == AdminLevel::SuperUser
		end

		it 'should not be equal to "None"' do
			AdminLevel::SuperUser.should_not == 'None'
		end

		it 'should not be equal to "Admin"' do
			AdminLevel::SuperUser.should_not == 'Admin'
		end

		it 'should be equal to "SuperUser"' do
			AdminLevel::SuperUser.should == 'SuperUser'
		end

		it 'should not be equal to 0' do
			AdminLevel::SuperUser.should_not == 0
		end

		it 'should not be equal to 1' do
			AdminLevel::SuperUser.should_not == 1
		end

		it 'should be equal to 2' do
			AdminLevel::SuperUser.should == 2
		end
	end

end