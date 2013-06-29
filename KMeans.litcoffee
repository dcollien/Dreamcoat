KMeans++ Clusterer
-------------------

    class KMeans

This class is a KMeans clusterer with an intelligent starting cluster selection. Data points can be
added to a cluster with a weighing, rather than adding a point multiple times. Each cluster stores
a mean (centroid) vector and points are moved to closer clusters until such movement no longer occurs.

The clusterer is constructed with the number of clusters to work with, and the dimensionality of the
space over which clustering is taking place. The constructor instantiates the required number of
Cluster objects.

      constructor: (numClusters, numDimensions) ->
        @numClusters = numClusters
        @clusters = ((new Cluster numDimensions) for i in [0...numClusters])
      
Initialise the list of points to cluster. Each point is a pair of [data, weight] where data is a vector value.
The weights may refer to how many times a vector is represented within the full set of data points.

      setPoints: (points) ->
        @dataPoints = ((new DataPoint data, weight) for [data, weight] in points)
      
This method performs the clustering of the added data points into Cluster objects. 
Each clustering step returns how many points moved between clusters, and clustering stops when no more moves
are made. Returned are the cluster objects after clustering.

      performCluster: () ->
        @initClusters()

        loop
          movesMade = @clusterStep()
          break if movesMade is 0
        
        return @clusters
      
With KMeans it is important that the selection of the initial cluster centers are spread out over the 
data points. This method intelligently selects an initial center point for each cluster, based on a 
randomised first choice.

      initClusters: () ->
        # select intelligent initial cluster centers
        numPoints  = @dataPoints.length
        
        # choose an initial center uniformly at random
        firstCenterIndex = Math.floor (Math.random() * numPoints)

        @clusters[0].addPoint @dataPoints[firstCenterIndex]
        
        # init the other clusters with centers at a balanced distance
        for cluster in @clusters[1..]
          maxDist = 0
          bestCenter = null
          
          # find a point furthest from all the current centers
          for point in @dataPoints
            # skip already assigned centers
            if not point.cluster?
              minDist = @nearestClusterDistance point

              if minDist > maxDist
                # the nearest cluster is farther than
                # the farthest point
                maxDist = minDist
                bestCenter = point
          
          cluster.addPoint bestCenter
        
This method finds the distance to the nearest cluster from a DataPoint (used by initClusters).
It does not keep track of which cluster is at this distance.

      nearestClusterDistance: (point) ->
        minDist = Number.POSITIVE_INFINITY

        for cluster in @clusters when (cluster? and cluster.size > 0)
          minDist = Math.min minDist, (cluster.getDistanceTo point)

        return minDist
      
This method finds the Cluster nearest a DataPoint.

      nearestClusterTo: (point) ->
        nearestCluster = null
        nearestDistance = Number.POSITIVE_INFINITY

        for cluster in @clusters when (cluster? and cluster.size > 0)
          if not nearestCluster?
            # ensure a nearestCluster is always assigned
            nearestCluster = cluster
            nearestDistance = nearestCluster.getDistanceTo point
          else
            distance = cluster.getDistanceTo point
            if distance < nearestDistance
              # nearest cluster so far
              nearestCluster  = cluster
              nearestDistance = distance

        return nearestCluster
      
This method attempts to reassign a DataPoint to a new Cluster. A data point is assigned to the given cluster
if it has not yet been assigned to a cluster, or if the cluster to which it was previously assigned has 
more than 1 data point (the last data point in a cluster will not be removed).

This method returns true if (and only if) the point was indeed assigned to a new cluster.

      reassignPoint: (point, cluster) ->
        currentCluster = point.cluster
        wasAbleToAssign = false
        
        if not currentCluster?
          # no cluster associated with this point,
          # add it to the new cluster
          cluster.addPoint point
          wasAbleToAssign = true
        
        else if currentCluster.size > 1 and cluster isnt currentCluster
          # move it from its current cluster to a
          # nearer cluster
          currentCluster.removePoint point
          cluster.addPoint point
          wasAbleToAssign = true
        
        return wasAbleToAssign
      
This method runs each step of the clustering, returning how many points were moved between clusters in this step.
Each point is moved from its existing cluster to the cluster which is currently nearest to the data point. Points
are not moved if it would cause a cluster to become empty, and if the point is already in its nearest cluster then
this is not counted.

      clusterStep: ->
        numMoves = 0
        
        # reassign points to their nearest cluster
        # and increment the number of moves made when reassignment succeeds
        for point in @dataPoints
          nearestCluster = @nearestClusterTo point
          numMoves++ if @reassignPoint point, nearestCluster
            
        return numMoves

DataPoint (used by clusterer)
------------------------------

Stores a data vector, a weighting and the current cluster to which this point is assigned.

    class DataPoint  
      constructor: (@data, @weight=1, @cluster=null) ->
  

Cluster object
----------------

Stores the size (cardinality) of the cluster, the sum of all the data points (multiplied by weights) contained
within the cluster as well as the dimensionality of the data vector.

    class Cluster

A cluster is constructed with the dimensionality of the space being clustered. Its starting size is 0, and no
sum is initialised. An array with the length of the number of dimensions is allocated for convenient looping.

      constructor: (numDimensions) ->
        @size = 0
        @dimensions = [0...numDimensions]
        @sum = (0 for i in @dimensions)

When a DataPoint is added to a cluster, the point's data vector scaled by its weight is added to the cluster's
sum. The cardinality is also increased by the point's weight. The combination of sum and size stores the cluster's
mean. This operation therefore shifts the mean of the cluster by the addition of a weighted data point.

      addPoint: (point) ->
        @size += point.weight
        @sum[i] += point.data[i] * point.weight for i in @dimensions
        point.cluster = @
      
removePoint is the inverse of addPoint, subtracting the weighted point from the cluster. This operation shifts the 
mean of the cluster by the subtraction of the weighted data point.

      removePoint: (point) ->
        point.cluster = null
        @size -= point.weight
        @sum[i] -= point.data[i] * point.weight for i in @dimensions
        
This method calculates the mean from the sum and size of the cluster.

      getMean: () -> (@sum[i] / @size for i in @dimensions)
      
The getDistanceTo method is called on a Cluster to determine the distance from a given DataPoint to the cluster.
The distance function implemented is the square of the Euclidean distance of the data point to the mean of the cluster.

      getDistanceTo: (point) ->
        centroid = @getMean()
        squaredDist = 0

        for i in @dimensions
          diff = centroid[i] - point.data[i]
          squaredDist += diff * diff

        return squaredDist
