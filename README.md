# LazyMapper

Wraps a Hash and lazily maps its attributes to rich domain objects using either a set of default mappers (for Ruby's built-in types), or custom mappers specified by the client.

The mapped values are memoized.

Example:

    class Foo < LazyMapper
      one :id, Integer, from: 'iden'
      one :created_at, Time
      one :amount, Money, map: Money.method(:parse)
      many :users, User, map: ->(u) { User.new(u) }
    end

## Documentation

See [RubyDoc](https://www.rubydoc.info/gems/lazy_mapper/0.2.1)

## License

See [LICENSE](./LICENSE) file.
