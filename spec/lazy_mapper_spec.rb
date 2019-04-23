# frozen_string_literal: true

require 'spec_helper'
require 'lazy_mapper'

describe LazyMapper::Model do

  describe 'when constructed from unmapped data' do

    subject(:instance) { klass.from unmapped_data }

    let(:unmapped_data) {
      {
        'createdAt' => '2015-07-27',
        'updatedAt' => ['2015-01-01', '2015-01-02'],
        'foo'       => '42',
        'blue'      => true
      }
    }
    let(:klass) {
      t = type
      m = map
      Class.new described_class do
        one :created_at, Date
        many :updated_at, Date
        one :foo, t, map: m, default: 666
        is :blue?
      end
    }
    let(:mapper) { spy 'mapper', map: 42 }
    let(:map) { ->(x) { mapper.map(x) } }
    let(:type) { Integer }

    context 'if the supplied data is nil' do
      let(:unmapped_data) { nil }

      it { is_expected.to be_nil }
    end

    context 'when invalid data is supplied' do
      let(:unmapped_data) { 'not a hash' }

      it 'fails with a TypeError' do
        expect { instance }.to raise_error(TypeError)
      end
    end

    context 'when valid data is supplied' do

      it 'maps primitives to domain objects' do
        expect(instance.created_at).to eq(Date.new(2015, 7, 27))
      end

      it 'maps arrays of primitives to arrays of domain objects' do
        expect(instance.updated_at).to be_a(Array)
        expect(instance.updated_at.first).to be_a(Date)
        expect(instance).to be_blue
      end

      it 'memoizes mapped value so that potentially expensive mappings are performed just once' do
        3.times do
          expect(instance.foo).to eq(42)
        end
        expect(mapper).to have_received(:map).exactly(1).times.with('42')
      end

      it 'only shows already mapped values, when inspected' do
        stub_const 'MyModel', klass
        instance.created_at
        expect(instance.inspect).to eq '<MyModel created_at: #<Date: 2015-07-27 ((2457231j,0s,0n),+0s,2299161j)> >'
      end

      context 'if the mapped value is nil' do
        let(:map) { -> x { mapper.map(x); nil } }

        it 'even memoizes that' do
          3.times do
            expect(instance.foo).to be_nil
          end
          expect(mapper).to have_received(:map).exactly(1).times.with('42')
        end
      end

      context 'when the model has circular references' do

        subject(:instance) { foo }

        let(:foo) { klass_foo.from 'bar' => 'bar' }
        let(:bar) { klass_bar.from 'foo' => 'foo' }
        let(:foo_builder) { proc { foo } }
        let(:bar_builder) { proc { bar } }

        let(:klass_foo) {
          b = bar_builder
          Class.new described_class do
            one :bar, Object, map: b
          end
        }

        let(:klass_bar) {
          b = foo_builder
          Class.new described_class do
            one :foo, Object, map: b
          end
        }

        it 'avoids infinit recursion, when inspected' do
          stub_const('Bar', klass_bar)
          stub_const('Foo', klass_foo)
          foo.bar.foo
          expect(foo.inspect).to eq('<Foo bar: <Bar foo: <Foo ... > > >')
        end
      end
    end

    describe 'the :from option' do

      let(:klass) {
        Class.new described_class do
          one :baz, Integer, from: 'BAZ'
          is :fuzzy?, from: 'hairy'
          is :sweet?, from: 'sugary'
        end
      }

      let(:unmapped_data) { { 'BAZ' => 999, 'hairy' => true } }

      it 'specifies the name of the attribute in the unmapped data' do
        expect(instance.baz).to eq(999)
      end

      it { is_expected.to be_fuzzy }
      it { is_expected.to_not be_sweet }
    end

    context "if the mapper doesn't map to the correct type" do

      let(:klass) {
        Class.new described_class do
          one :bar, Float, map: ->(x) { x.to_s }
        end
      }

      it 'fails with a TypeError when an attribute is accessed' do
        instance = klass.from 'bar' => 42
        expect { instance.bar }.to raise_error(TypeError)
      end
    end

    it 'supports adding custom type mappers to instances' do
      type = Struct.new(:val1, :val2)
      klass = Class.new described_class do
        one :composite, type
      end

      instance = klass.from 'composite' => '123 456'
      instance.add_mapper_for(type) { |unmapped_value| type.new(*unmapped_value.split(' ')) }

      expect(instance.composite).to eq type.new('123', '456')

      instance = klass.new composite: type.new('abc', 'cde')
      expect(instance.composite).to eq type.new('abc', 'cde')
    end

    it 'supports injection of customer mappers during instantiation' do
      type = Struct.new(:val1, :val2)
      klass = Class.new described_class do
        one :foo, type
        one :bar, type
      end

      instance = klass.from({ 'foo' => '123 456', 'bar' => 'abc def' },
                            mappers: {
                              foo: ->(f) { type.new(*f.split(' ').reverse) },
                              type => ->(t) { type.new(*t.split(' ')) }
                            })

      expect(instance.foo).to eq type.new('456', '123')
      expect(instance.bar).to eq type.new('abc', 'def')
    end

    it 'expects the supplied mapper to return an Array if the unmapped value of a "many" attribute is not an array' do
      klass = Class.new described_class do
        many :foos, String, map: ->(v) { return v.split '' }
        many :bars, String, map: ->(v) { return v }
      end

      instance = klass.from 'foos' => 'abc', 'bars' => 'abc'

      expect(instance.foos).to eq %w[a b c]
      expect { instance.bars }.to raise_error(TypeError)
    end

    context 'when it is derived from another LazyMapper' do
      let(:klass) { Class.new(base) }
      let(:composite_type) { Struct.new(:val1, :val2) }
      let(:new_type) { Class.new }
      let(:new_type_mapper) { new_type.method(:new) }
      let(:base) {
        type = composite_type
        Class.new(described_class) do
          default_value_for type, type.new('321', '123')
          mapper_for type, ->(unmapped_value) { type.new(*unmapped_value.split(' ')) }
          one :composite, type
        end
      }

      it 'inherits attributes' do
        expect(klass.attributes.keys).to eq [:composite]
        expect(instance).to respond_to(:composite)
      end

      it 'inherits default values' do
        expect(instance.composite).to eq composite_type.new('321', '123')
      end

      it 'inherits default mappers' do
        expect(klass.from('composite' => 'abc def').composite).to eq composite_type.new('abc', 'def')
      end

      it 'inherits default mappers that are added to its parent after it has been defined', wip: true do
        expect(klass.mappers[new_type]).to be_nil
        base.mapper_for new_type, new_type_mapper
        expect(base.mappers[new_type]).to eq new_type_mapper
        expect(klass.mappers[new_type]).to eq new_type_mapper
      end
    end
  end

  context 'when constructed with .new' do

    subject(:instance) { klass.new values }
    let(:values) { {} }

    let(:klass) {
      Class.new described_class do
        one :title, String
        one :count, Integer
        one :rate, Float
        one :tags, Array
        one :widget, Object
        one :things, Array, default: ['something']
        is  :green?
        has :flowers?
        many :cars, Object
      end
    }

    context 'when values are provided' do

      let(:values) {
        {
          title:  'A title',
          count:  42,
          rate:   3.14,
          tags:   %w[red hot],
          widget: Date.new,
          things: %i[one two three],
          green?: true
        }
      }

      it 'uses those values' do
        values.each do |name, value|
          expect(instance.send(name)).to eq(value)
        end
      end

      context 'if a value given in the constructor is not of the specified type' do
        let(:values) {
          { title: :'Not a string' }
        }

        it 'fails with a TypeError' do
          expect { instance }.to raise_error(TypeError)
        end
      end
    end

    context 'when no values are provided' do

      it 'has sensible default values for primitive types' do
        expect(instance.title).to eq('')
        expect(instance.count).to eq(0)
        expect(instance.rate).to eq(0.0)
        expect(instance.widget).to be_nil
        expect(instance.tags).to eq []
      end

      it 'uses the supplied default values' do
        expect(instance.things).to eq(['something'])
      end

      it 'falls back to nil in all other cases' do
        expect(instance.widget).to be_nil
      end

      it 'dosn\'t share its default values with other instances' do
        instance1 = klass.new
        instance2 = klass.new
        instance1.tags << 'dirty'
        instance1.things.pop
        expect(instance2.tags).to be_empty
        expect(instance2.things).to_not be_empty
      end

      it 'still includes every attribute when converted to Hash' do
        expect(instance.to_h).to eq(
          title:    '',
          count:    0,
          rate:     0.0,
          tags:     [],
          widget:   nil,
          things:   ['something'],
          green?:   false,
          flowers?: false,
          cars:     []
        )
      end
    end
  end
end
