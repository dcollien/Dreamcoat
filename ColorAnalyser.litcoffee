Color Analyser
----------------


    class ColorAnalyser
      constructor: (img, canvas, maxColorBits=8) ->
        @octree = new Octree maxColorBits
        @loadCanvas img, canvas
        
      loadCanvas: (img, canvas) ->
        context = canvas.getContext '2d'
        
        @imgWidth = img.width
        @imgHeight = img.height

        canvas.width = @imgWidth
        canvas.height = @imgHeight
        
        context.drawImage img, 0, 0
        @imageData = context.getImageData 0, 0, @imgWidth, @imgHeight

      getPixel: (x, y, channels=3) -> 
        idx = (y * @imgWidth + x) * 4
        (@imageData.data[idx + channel] for channel in [0...channels])

      detectBackground: () ->
        top    = (@getPixel x, 0              for x in [0...@imgWidth])
        bottom = (@getPixel x, (@imgHeight-1) for x in [0...@imgWidth])
        left   = (@getPixel 0, y              for y in [0...@imgHeight])
        right  = (@getPixel (@imgWidth-1), y  for y in [0...@imgHeight])

        border = ((top.concat bottom).concat left).concat right

        colorFreqs = {}

        for color in border
          if colorFreqs[color.toString()]?
            colorFreqs[color.toString()]++
          else
            colorFreqs[color.toString()] = 1

        bgColor = top[0]
        mostFrequent = 0
        for color, freq of colorFreqs
          if freq > mostFrequent
            bgColor = color.split(',').map (x) -> parseInt x
            mostFrequent = freq

        return bgColor

      rgbToHsl: (r, g, b) ->
        r /= 255
        g /= 255
        b /= 255
        max = Math.max(r, g, b)
        min = Math.min(r, g, b)
        l = (max + min) / 2
     
        if max == min
          h = s = 0 # achromatic
        else
          d = max - min
          s = if l > 0.5 then d / (2 - max - min) else d / (max + min)
     
          switch max
            when r
              h = (g - b) / d + (if g < b then 6 else 0)
            when g
              h = (b - r) / d + 2
            when b
              h = (r - g) / d + 4
     
          h /= 6
     
        [h, s, l]
     
      #
      # Converts an HSL color value to RGB. Conversion formula
      # adapted from http://en.wikipedia.org/wiki/HSL_color_space.
      # Assumes h, s, and l are contained in the set [0, 1] and
      # returns r, g, and b in the set [0, 255].
      #
      # @param   Number  h       The hue
      # @param   Number  s       The saturation
      # @param   Number  l       The lightness
      # @return  Array           The RGB representation
      #
      hslToRgb: (h, s, l) ->
        if s == 0
          r = g = b = l # achromatic
        else
          hue2rgb = (p, q, t) ->
            if t < 0 then t += 1
            if t > 1 then t -= 1
            if t < 1/6 then return p + (q - p) * 6 * t
            if t < 1/2 then return q
            if t < 2/3 then return p + (q - p) * (2/3 - t) * 6
            return p
     
          q = if l < 0.5 then l * (1 + s) else l + s - l * s
          p = 2 * l - q
          r = hue2rgb(p, q, h + 1/3)
          g = hue2rgb(p, q, h)
          b = hue2rgb(p, q, h - 1/3)
     
        [r * 255, g * 255, b * 255]

      chooseTextColor: (backgroundColor) ->
        [r, g, b] = backgroundColor


        luminance = 1 - (0.299 * r + 0.587 * g + 0.114 * b)

        [h, s, l] = @rgbToHsl r, g, b

        # rotate hue
        h += 0.5
        if h > 1 then h -= 1

        s = (1 - s) * 0.25

        if luminance < 0.5
          l *= 1.2
        else
          l /= 1.2

        l = (1 - l) * (1 - l)

        return (@hslToRgb h, s, l).map Math.floor

      analyseImage: (paletteSize, background=null, ignoreGrey=false) ->
        if not background? then background = @detectBackground()
        [palette, numVectors] = @getClusteredPalette paletteSize, 1, 1024, background, 32, ignoreGrey
        return [palette, numVectors]

      getClusteredPalette: (numClusters, threshold, paletteSize, exclude, error, ignoreGrey) ->
        [palette, numVectors] = @getThresholdedPalette threshold, paletteSize, exclude, error, ignoreGrey

        clusterer = new KMeans numClusters, 3
        clusterer.setPoints palette
        clusters = clusterer.performCluster()

        colors = ([cluster.getMean(), cluster.size] for cluster in clusters)

        return [colors, numVectors]

      getThresholdedPalette: (threshold, paletteSize, exclude, error, ignoreGrey) ->
        [colors, numVectors] = @getPalette paletteSize, exclude, error, ignoreGrey

        colors.sort (a, b) -> (b[1] - a[1])

        newColors = []

        sum = 0
        for color in colors
          newColors.push color
          sum += color[1]

          break if sum > (numVectors * threshold)

        return [newColors, numVectors] 


      getFilteredPalette: (stdDeviations, paletteSize, exclude, error, ignoreGrey) ->
        [colors, numVectors] = @getPalette paletteSize, exclude, error, ignoreGrey

        numColors = 0
        freqSum = 0
        for i in [0...colors.length]
          [color, freq] = colors[i]

          freqSum += freq
          numColors++

        meanFrequency = freqSum / numColors

        stdDevSum = 0
        for i in [0...colors.length]
          [color, freq] = colors[i]
          meanDiff = (freq - meanFrequency)
          stdDevSum += (meanDiff * meanDiff)

        stdDevFrequency = Math.sqrt (stdDevSum/numColors)

        filteredColors = ([color, freq] for [color, freq] in colors when Math.abs(freq - meanFrequency) < (stdDevFrequency * stdDeviations))

        return [filteredColors, numVectors]


      getPalette: (paletteSize, exclude, error, ignoreGrey) ->
        if not error? then error = 0

        pixelData = @imageData.data

        for i in [0...pixelData.length] by 4
          r = pixelData[i]
          g = pixelData[i+1]
          b = pixelData[i+2]
          a = pixelData[i+3]

          isExcluded = false
          if exclude?
            [er, eg, eb] = exclude
          
            rIsWithinError = (er - error) < r < (er + error)
            gIsWithinError = (eg - error) < g < (eg + error)
            bIsWithinError = (eb - error) < b < (eb + error)

            isExcluded = rIsWithinError and gIsWithinError and bIsWithinError
          
          excludeGrey = false

          if ignoreGrey
            rg = Math.abs( r - g ) < error
            rb = Math.abs( r - b ) < error
            gb = Math.abs( g - b ) < error
            
            excludeGrey = ignoreGrey and rg and rb and gb

            isExcluded = isExcluded or excludeGrey
          
          
          if not isExcluded then @octree.insertVector [r, g, b]

        numVectors = @octree.numVectors
        return [(@octree.reduceToSize paletteSize), numVectors]
        
        