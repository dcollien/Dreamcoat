Octree
-------

<small>David Collien, 2013</small>

-------------------------------------------------------------------------------------------------------------------------

An octree data structure for quantizing a discrete 3D vector space.

    class Octree

These are fixed properties of an octree: each node can be represented as a cube,
each cube can be split into 8 equal sub-cubes. It is therefore a tree with a branching factor of 8.
Each cube represents a 3 dimensional vector space.

      @branching  = 8
      @dimensions = 3

An octree is constructed by supplying the maximum number of bits used to represent value in a vector.
Each level of the octree can be modelled by stripping a bit off each binary value. As this is a 3D space,
we end up with 3 stripped-off bits (one from each element of the vector) giving us the next 8 possible octants.
The input maximum number of bits is therefore equivalent to the depth of the octree we are constructing.

We also construct a root node for the octree, set the leaf count to zero and allocate an array of reducible nodes.
This array represents a stack of nodes at each level of the octree.

The last part of the constructor initialises bit masks for each level of the tree. A bitwise AND with the powers of 2
(in reverse order) will strip off the required bits for each level in the octree.

      constructor: (@maxBits = 8) ->
        @leafCount = 0
        @numVectors = 0
        @reducibleNodes = new Array (@maxBits + 1)    
        @levelMasks = [@maxBits-1..0].map (bit) -> Math.pow 2, bit

        # must be defined last
        @root = new OctreeNode @  


An equality function for two 3D vectors is included to assist with optimisations.

      isVectorEqual: (v1, v2) ->
        if not v1? or not v2? then return false
        
        #assert v1.length is Octree.dimensions and v2.length is Octree.dimensions
        
        for i in [0...Octree.dimensions]
          if v1[i] isnt v2[i]
            return false
        
        return true

When inserting a vector into the octree, it is tested against the last node which was added.
This helps if many of the same vector value are added in sequence, when just the count of the most
recently added node can be incremented immediately, rather than travelling down the tree from the root node.

Vectors are inserted at the root node, which propagates the value down the tree to its correct position.

      insertVector: (newVect) ->
        # test if we've just added this vector to the tree,
        # if so, we can insert the value here without
        # searching the whole tree
        if @prevNode? and (@isVectorEqual newVect, @prevVect)
          @prevNode.insertVector newVect, @
        else
          @prevVect = newVect
          @prevNode = @root.insertVector newVect, @

        @numVectors++

The reduce operation on an octree finds the current lowest level of the tree which contain internal nodes,
takes the last node to be added at this level and subsumes the child leaves of this node. This node then
becomes a leaf itself.
    
      reduce: () ->
        # find the deepest level containing at least one reducible node
        levelIndex = @maxBits - 1
        while levelIndex > 0 and not @reducibleNodes[levelIndex]?
          levelIndex--
        
        # reduce the node most recently added to the list at this level
        node = @reducibleNodes[levelIndex]
        @reducibleNodes[levelIndex] = node.nextReducible
        
        # reduce the node and decrement the leaf count
        # by the number of nodes pruned
        @leafCount -= node.reduce()
        
        # invalidate the previous node
        @prevNode = null

The octree can be reduced to a certain number of leaf nodes. The reduce operation is
called repeatedly while the the number of leaf nodes is greater than the input number
of items.

      reduceToSize: (itemCount) ->
        # reduce down to the required size
        while @leafCount > itemCount
          @reduce()
        
        return @root.getData()


Octree Node
-------------

Each 3D vector inserted into the octree is stored and aggregated by an OctreeNode. 

    class OctreeNode

An octree node is constructed with the level of the tree where the node is to be placed (defaults
to zero, a root node), as well as the octree it is a member of.

This constructor determines if it is a leaf node. If it is a leaf node, the count of leaves in
the octree is incremented. Otherwise, it is pushed on to the stack of reducible nodes for this
level of the tree and an array of 8 children (for each octant cube in the 3D space of this node)
is allocated.

Octree nodes store a mean value, which is calculated from its children upon reduction. This mean
vector is also allocated for the node upon construction, but no value is given to it at this stage.

      constructor: (octree, level=0) ->
        # is it a leaf node?
        @isLeaf = (level == octree.maxBits)

        # the mean vector for this node
        @mean   = (0 for i in [0...Octree.dimensions])

        # how many times this vector's data has been added
        @count  = 0
        
        if @isLeaf
          octree.leafCount++
          @nextReducible = null
          @children = null
        else
          @nextReducible = octree.reducibleNodes[level]
          octree.reducibleNodes[level] = @
          @children = new Array Octree.branching
    
When inserting a vector into a node, its sub-tree is checked to see where the value should be stored.
This method takes in the vector to incorporate into the tree, the tree which this node is a member of
(this is not stored by each node) and optionally, the depth at which to start searching for the correct
place to save the vector value. This method is recursively called, building any required internal nodes
until a leaf node is reached in which to store the vector value. This method returns the leaf node where
the value is inserted.

      insertVector: (v, octree, level=0) ->
        #assert v.length is Octree.dimensions

        if @isLeaf
          # keep track of how many times this vector was added
          @count++

          # add this vector's data to the leaf
          for i in [0...Octree.dimensions]
            if not @mean[i]? or @count is 1
              # if this is the first value to add, just set its value
              @mean[i] = v[i]
            else
              # otherwise, fold it into the mean value of this node
              @mean[i] = (@mean[i] * (@count - 1) + v[i]) / @count
          return @
        else
          index = @getIndex v, level, octree
          child = @children[index]
          
          # create a child node if one doesn't exist
          if not child?
            child = new OctreeNode octree, (level + 1)
            @children[index] = child
          
          # continue to a leaf node
          return child.insertVector v, octree, (level + 1)
    
The children of a node are stored in an array, indexed by stripping a bit from the binary representation
of the value. The depth of the node (its level in the octree) determines which bit of the vector element is looked at to
provide the index. e.g. depth 0 (root node) looks at the most significant bit, the lowest level in the tree looks at the
least significant bit. This method determines the index for a child, based on the depth level of the node in the octree
and the vector value being added. It is used by insertVector to build the internal nodes of the octree.

      getIndex: (v, level, octree) ->
        shift = octree.maxBits - 1 - level
        index = 0
        for i in [0...Octree.dimensions]
          reverseIndex = Octree.dimensions - 1 - i
          index |= (v[i] & octree.levelMasks[level]) >> (shift - reverseIndex)
          
        return index

This method removes the child nodes under this node and merges their values this node
(in this case the mean vector and a count of how many values have been combined into this node).
This node then becomes a leaf node.

      reduce: () ->
        if @isLeaf then return 0

        numChildren = 0
        
        # combine all children's information into this node (vector mean and count)
        for childIndex in [0...Octree.branching]
          child = @children[childIndex]
          if child?
            # combine mean with child
            newCount = @count + child.count

            for i in [0...Octree.dimensions]
              nodeSum  = @mean[i] * @count
              childSum = child.mean[i] * child.count
              @mean[i] = (nodeSum + childSum) / newCount

            # update count
            @count = newCount

            numChildren++

            # release this child node for GC
            @children[childIndex] = null
        
        # reduced to a leaf
        @isLeaf = true
        
        # returns the number of nodes removed by this reduction
        return (numChildren - 1)
    
This method conveniently outputs the values stored in the tree in a flattened form.
Returned is an array of vector means for each node, paired with the count of how many values have been
combined into this mean. getData can be called without any arguments, where it will gather child nodes
recursively for the sub-tree under this node.

      getData: (data, index) ->
        # flatten into an array of vector means and counts
        if not data?
          data = @getData [], 0
        else if @isLeaf
          data.push [@mean, @count]
        else
          for i in [0...Octree.branching]
            if @children[i]?
              data = @children[i].getData data, index
        return data

