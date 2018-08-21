# frozen_string_literal: true

require 'spec_helper'
require 'lazy_mapper'

describe LazyMapper do

  describe '.from_json' do

    subject(:instance) { klass.from_json json }

    let(:json) { nil }
    let(:klass) {
      t = type
      m = map
      Class.new LazyMapper do
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
      it { is_expected.to be_nil }
    end

    context 'when invalid data is supplied' do
      let(:json) { 'not a hash' }

      it 'fails with a TypeError' do
        expect { instance }.to raise_error(TypeError)
      end
    end

    context 'when valid data is supplied' do

      let(:json) {
        {
          'createdAt' => '2015-07-27',
          'updatedAt' => ['2015-01-01', '2015-01-02'],
          'foo'       => '42',
          'blue'      => true
        }
      }

      it 'maps JSON attributes to domain objects' do
        expect(instance.created_at).to eq(Date.new(2015, 7, 27))
      end

      it 'maps arrays of JSON values to arrays of domain objects' do
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

      context 'if the mapped value is nil' do
        let(:map) { -> x { mapper.map(x); nil } }

        it 'even memoizes that' do
          3.times do
            expect(instance.foo).to be_nil
          end
          expect(mapper).to have_received(:map).exactly(1).times.with('42')
        end
      end
    end

    describe 'the :from option' do

      let(:klass) {
        Class.new LazyMapper do
          one :baz, Integer, from: 'BAZ'
          is :fuzzy?, from: 'hairy'
          is :sweet?, from: 'sugary'
        end
      }

      let(:json) { { 'BAZ' => 999, 'hairy' => true } }

      it 'specifies a different name in the JSON object for the attribute' do
        expect(instance.baz).to eq(999)
      end

      it { is_expected.to be_fuzzy }
      it { is_expected.to_not be_sweet }
    end

    context "if the mapper doesn't map to the correct type" do

      let(:klass) {
        Class.new LazyMapper do
          one :bar, Float, map: ->(x) { x.to_s }
        end
      }

      it 'fails with a TypeError when an attribute is accessed' do
        instance = klass.from_json 'bar' => 42
        expect { instance.bar }.to raise_error(TypeError)
      end
    end

    it 'supports adding custom type mappers to instances' do
      type = Struct.new(:val1, :val2)
      klass = Class.new LazyMapper do
        one :composite, type
      end

      instance = klass.from_json 'composite' => '123 456'
      instance.add_mapper_for(type) { |unmapped_value| type.new(*unmapped_value.split(' ')) }

      expect(instance.composite).to eq type.new('123', '456')

      instance = klass.new composite: type.new('abc', 'cde')
      expect(instance.composite).to eq type.new('abc', 'cde')
    end

    it 'supports adding default mappers to derived classes' do
      type = Struct.new(:val1, :val2)

      klass = Class.new LazyMapper do
        mapper_for type, ->(unmapped_value) { type.new(*unmapped_value.split(' ')) }
        one :composite, type
      end

      instance = klass.from_json 'composite' => '123 456'
      expect(instance.composite).to eq type.new('123', '456')
    end

    it 'supports injection of customer mappers during instantiation' do
      type = Struct.new(:val1, :val2)
      klass = Class.new LazyMapper do
        one :foo, type
        one :bar, type
      end

      instance = klass.from_json({ 'foo' => '123 456', 'bar' => 'abc def' },
                                 mappers: {
                                   foo: ->(f) { type.new(*f.split(' ').reverse) },
                                   type => ->(t) { type.new(*t.split(' ')) }
                                 })

      expect(instance.foo).to eq type.new('456', '123')
      expect(instance.bar).to eq type.new('abc', 'def')
    end

    it 'expects the supplied mapper to return an Array if the unmapped value of a "many" attribute is not an array' do
      klass = Class.new LazyMapper do
        many :foos, String, map: ->(v) { return v.split '' }
        many :bars, String, map: ->(v) { return v }
      end

      instance = klass.from_json 'foos' => 'abc', 'bars' => 'abc'

      expect(instance.foos).to eq %w[a b c]
      expect { instance.bars }.to raise_error(TypeError)
    end
  end

  context 'construction' do

    subject(:instance) { klass.new values }
    let(:values) { {} }

    let(:klass) {
      Class.new LazyMapper do
        one :title, String
        one :count, Integer
        one :rate, Float
        one :tags, Array
        one :widget, Object
        one :things, Array, default: ['something']
        is  :green?
        has :flowers?
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

      it 'have sensible fallback values for primitive types' do
        expect(instance.title).to eq('')
        expect(instance.count).to eq(0)
        expect(instance.rate).to eq(0.0)
        expect(instance.widget).to be_nil
        expect(instance.tags).to eq []
      end

      it 'use the supplied default values' do
        expect(instance.things).to eq(['something'])
      end

      it 'fall back to nil in all other cases' do
        expect(instance.widget).to be_nil
      end

      it 'don\'t share their default values between instances' do
        instance1 = klass.new
        instance2 = klass.new
        instance1.tags << 'dirty'
        instance1.things.pop
        expect(instance2.tags).to be_empty
        expect(instance2.things).to_not be_empty
      end
    end
  end
end
