### Carpaccio [![Swift Package Manager compatible](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager) [![build status](https://gitlab.com/sashimiapp-public/Carpaccio/badges/master/build.svg)](https://gitlab.com/sashimiapp-public/Carpaccio/commits/master)
##### Pure Swift goodness for RAW and other image + metadata handling

Carpaccio is a Swift library for macOS and iOS that allows fast decoding of image data & EXIF metadata from file formats supported by CoreImage (including all the various RAW file formats supported, using the CoreImage RAW decoding capability).

- thumbnails
- metadata
- full sized image 

Carpaccio uses multiple CPU cores efficiently in parallel for all of metadata, thumbnail and image data decoding.

There are no 3rd party dependencies (CoreImage filter is used for RAW decoding).

**NOTE! If you are looking at this on GitHub, please be noted that the primary source for Carpaccio is to be found at [gitlab.com/sashimiapp-public/carpaccio.git](https://gitlab.com/sashimiapp-public/carpaccio.git).**

#### INSTALLATION

##### Swift Package Manager

Add Carpaccio to your Swift package as a dependency by adding the following to your Package.swift file in the dependencies array:

```swift
.package(url: "https://github.com/mz2/Carpaccio.git", from: "<version>")
```

If you are using Xcode 11 or newer, you can add Carpaccio by entering the URL to the repository via the File menu:

```
File > Swift Packages > Add Package Dependency...
```

#### USAGE

Adapting from a test included in the test suite for the framework, here's how you can use Carpaccio:

```Swift
    let converter = RAWImageLoader(imageURL: img1URL, thumbnailScheme: .fullImageWhenThumbnailMissing)

    converter.loadThumbnailImage(handler: { thumb, imageMetadata in
        // deal with thumbnail + metadata 
    }) { error in
        // deal with the error 
    }
```

There's a lot more to it though, including different schemes for loading thumbnails or using full size images when thumbnails are not found or are too small, and decoding thumbnails / full images at a specified maximum resolution. 

Documentation and tests are minimal so for now you'll just need to explore the API to discover all the good stuff. Please feel free to make suggestions as issues on GitHub.

#### TODO

Carpaccio is still a very fresh and raw (har har) library and there are many tasks to make this a more generally useful library.

- [ ] Update usage examples.
- [x] Add tests for RAWs from a number of different camera vendors.
- [x] GitLab CI support.
- [x] iOS support.
