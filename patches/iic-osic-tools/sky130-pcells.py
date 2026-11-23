# sky130A の KLayout PCell（libs.tech/klayout/python/cells）を、今の gdsfactory 9 / kfactory で動くように直す。
#   python3 sky130-pcells.py <cells ディレクトリ>
#
# IIC-OSIC-TOOLS の _build/images/open_pdks/scripts/install_ciel.sh（commit f15ef6a）の
# sky130A の PCell 修正をそのまま Python にしたもの。
# SPDX-FileCopyrightText: 2022-2026 Harald Pretl and Georg Zachl, Johannes Kepler University
# SPDX-License-Identifier: Apache-2.0
import pathlib
import re
import sys

cells = pathlib.Path(sys.argv[1])

# gdsfactory >= 8 does not support the "A-B" boolean operation string anymore; use "-" instead.
for py in cells.rglob("*.py"):
    src = py.read_text()
    new = re.sub(r'operation= *"A-B"', 'operation="-"', src)
    if new != src:
        py.write_text(new)

# cells/pdk.py was written against kfactory 0.x internals: the private _get_default_kcl() and
# KCell._kdb_cell were removed in kfactory >= 1.x, and kfactory >= 1.x locks cells produced by
# cached cell functions, which breaks the scale_and_snap grid snapping in take_component().
pdk = cells / "pdk.py"
src = pdk.read_text()

old = "  kf.kcell._get_default_kcl().clear()\n"
new = """  # kfactory >= 1.x removed the private _get_default_kcl(); the default
  # layout is available as kf.kcl there.
  try:
    kf.kcell._get_default_kcl().clear()
  except AttributeError:
    kf.kcl.clear()
"""
assert old in src, "pdk.py: _get_default_kcl pattern not found"
src = src.replace(old, new)

old = "  source_cell = c._kdb_cell\n"
new = """  # kfactory >= 1.x exposes the native cell as the public kdb_cell property.
  source_cell = getattr(c, "kdb_cell", None)
  if source_cell is None:
    source_cell = c._kdb_cell

  # kfactory >= 1.x locks cells produced by cached cell functions; unlock
  # them so scale_and_snap below may modify the cell tree.
  for cell in source_cell.layout().each_cell():
    if cell.locked:
      cell.locked = False
"""
assert old in src, "pdk.py: _kdb_cell pattern not found"
src = src.replace(old, new)
pdk.write_text(src)

# gdsfactory 9 removed Component.add_array, and gdsfactory >= 9.29 no longer auto-activates the
# generic PDK, which the drawing code relies on for layer resolution. In addition, gdsfactory reads
# the environment variable PDK (= sky130A here) as the name of a gdsfactory PDK module, which does
# not exist. Fall back to the generic PDK on any failure.
init = cells / "__init__.py"
init.write_text(init.read_text() + '''

def _gf9_compat():
    from typing import Optional

    import gdsfactory as gf

    def _add_array(self, component, columns=2, rows=2,
                   spacing=(100, 100), alias: Optional[str] = None):
        return self.add_ref(component=component, name=alias,
                            columns=columns, rows=rows,
                            column_pitch=spacing[0], row_pitch=spacing[1])

    if not hasattr(gf.Component, "add_array"):
        gf.Component.add_array = _add_array

    try:
        gf.get_active_pdk()
    except Exception:
        gf.gpdk.PDK.activate()


_gf9_compat()
''')
