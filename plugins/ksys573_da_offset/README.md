# Konami System 573 digital audio offset plugin

This plugin works by intercepting audio timer register reads in Konami System 573 digital hardware games.  It may not work perfectly in every game, depending on how it uses the timer register.

## Configuration

Here is an example **settings.json** commented to demonstrate how to add game-specific offsets, as well as a default offset to be used for all games on System 573 digital hardware without a specific offset specified.

A default offset of 28 ms is what I personally found to be most useful when running MAME on Windows, with the PortAudio sound output module using the WASAPI back-end for lowest audio latency.  I suggest you experiment with the default offset to figure out what works best for your setup.

```jsonc
{
    "default": "28ms", // Specify a default offset for all System 573 digital audio games unless overridden
                       // Setting this to 0 is the equivalent of disabling the default override
                       // Can be specified as a number of samples (e.g. 1234) or a delay in milliseconds (e.g. 1234ms)
    "overrides": {
        "ddrmax": 1234,  // Offset for the game "ddrmax" specified as a number of samples
        "ddr5m": "50ms", // Offset for the game "ddr5m" specified as a delay in milliseconds (automatically converted to a number of samples)
    }
}
```

## License

Copyright © 2022-2023 windyfairy

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS “AS IS” AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
