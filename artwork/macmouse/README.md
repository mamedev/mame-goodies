# Macintosh mouse integration layout

This layout contains a Mouse Integration view that causes an emulated Macintosh system’s mouse pointer to track the host mouse pointer.  The emulated system must be configured with a single screen.

Mouse and lightgun input must be disabled, and the `layout` plugin must be enabled.  Required settings may be applied with the following INI file lines or equivalent command line options:

```ini
override_artwork    macmouse
mouse               0
lightgun            0
plugins             1
plugin              layout
```

## License

Copyright and related rights waived via CC0 1.0 Universal.
