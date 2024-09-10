# Deprecated: Uses internal API ObjectSpace._id2ref and is replaced
#             by WeakIdConv.
module DRb
  class DRbIdConv

    # Convert an object reference id to an object.
    #
    # This implementation looks up the reference id in the local object
    # space and returns the object it refers to.
    def to_obj(ref)
      ObjectSpace._id2ref(ref)
    end

    # Convert an object into a reference id.
    #
    # This implementation returns the object's __id__ in the local
    # object space.
    def to_id(obj)
      case obj
      when Object
        obj.nil? ? nil : obj.__id__
      when BasicObject
        obj.__id__
      end
    end
  end
end
