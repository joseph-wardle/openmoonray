"""MoonRay tools for Houdini's VOP networks (Solaris Material Library).

Mirrors how SideFX builds its own Karma / USD Preview material builders
(voptoolutils.createMaskedMtlXSubnet): a plain `subnet` VOP with the standard
builder spare parms, so it behaves like every other builder in Houdini.
"""

import hou
import voptoolutils

# VOPs shown in the builder's TAB menu: MoonRay shaders (render mask
# "moonray"), USD preview shaders, and Houdini's generic utility/subnet nodes.
MOONRAY_TAB_MASK = "moonray USD {} {}".format(
    voptoolutils.UTILITY_NODES, voptoolutils.SUBNET_NODES
)

_SURFACE = "Vop::DW_MOONRAY::DwaBaseMaterial::1"
_DISPLACEMENT = "Vop::DW_MOONRAY::NormalDisplacement::1"

_DISPLACEMENT_NOTE = (
    "Not connected on purpose: binding any displacement makes MoonRay\n"
    "tessellate the geometry, even at zero height. Wire this into\n"
    "output_collect to displace."
)


def create_material_builder(kwargs, name="moonraymaterial"):
    """TAB tool entry point: a MoonRay material ready to edit.

    Inside:
        dwa_base_material   -> output_collect   (outputs:moonray:surface)
        preview_surface     -> output_collect   (outputs:surface, for the
                                                  GL viewport and other
                                                  renderers)
        normal_displacement    unconnected; see _DISPLACEMENT_NOTE
    """
    subnet = voptoolutils.genericTool(kwargs, "subnet", name)
    # No render context on the subnet: the collect authors each shader
    # under its own context (moonray vs. universal) from its render mask.
    voptoolutils._addMtlSubnetParms(
        subnet, MOONRAY_TAB_MASK, "", "MoonRay Material Builder"
    )

    for child in subnet.children():
        child.destroy()

    surface = subnet.createNode(_SURFACE, "dwa_base_material", exact_type_name=True)
    surface.setInputGroupExpanded(None, False)
    preview = subnet.createNode("usdpreviewsurface", "preview_surface")
    preview.setInputGroupExpanded(None, False)
    displacement = subnet.createNode(
        _DISPLACEMENT, "normal_displacement", exact_type_name=True
    )
    displacement.setComment(_DISPLACEMENT_NOTE)
    displacement.setGenericFlag(hou.nodeFlag.DisplayComment, True)

    output = subnet.createNode("collect", "output_collect")
    output.setInput(0, surface, 0)
    output.setInput(1, preview, 0)

    surface.setPosition(hou.Vector2(0.0, 0.0))
    preview.setPosition(hou.Vector2(0.0, -3.0))
    displacement.setPosition(hou.Vector2(0.0, -5.0))
    output.setPosition(hou.Vector2(4.0, -1.5))

    if subnet.parent().type().name() in ("materiallibrary", "matnet"):
        subnet.setMaterialFlag(True)
    return subnet
