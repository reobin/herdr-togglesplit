def boxeq($a; $b):
  $a.x == $b.x and $a.y == $b.y
  and $a.width == $b.width and $a.height == $b.height;

def inside($b; $o):
  $o.x <= $b.x and $o.y <= $b.y
  and ($b.x + $b.width) <= ($o.x + $o.width)
  and ($b.y + $b.height) <= ($o.y + $o.height)
  and (boxeq($b; $o) | not);

def flip:
  if . == "right" then "down"
  elif . == "down" then "right"
  else null end;

def keys:
  if . == "right" then {p: "x", z: "width", c: "y", w: "height"}
  elif . == "down" then {p: "y", z: "height", c: "x", w: "width"}
  else null end;

def kids($s; $splits; $panes):
  ([$splits[] | select(inside(.rect; $s.rect))]) as $subs
  | ([$subs[] | {kind: "split", r: .rect, ref: .}]
     + [$panes[] | select(inside(.rect; $s.rect))
        | {kind: "pane", r: .rect, ref: .}]
     | map(select(. as $c | (any($subs[]; inside($c.r; .rect)) | not)))) as $direct
  | if $s.direction == "right" then
      ($direct | sort_by(.r.x)
       | map(. + {share: (.r.width / $s.rect.width)}))
    elif $s.direction == "down" then
      ($direct | sort_by(.r.y)
       | map(. + {share: (.r.height / $s.rect.height)}))
    else null end;

def tiled($ks; $s):
  ($s.direction | keys) as $k
  | if $k == null then false
    else (($ks | length) >= 2)
      and ($ks[0].r[$k.p] == $s.rect[$k.p])
      and (($ks[-1].r[$k.p] + $ks[-1].r[$k.z])
           == ($s.rect[$k.p] + $s.rect[$k.z]))
      and all($ks[]; .r[$k.c] == $s.rect[$k.c]
                      and .r[$k.w] == $s.rect[$k.w])
      and all(range(1; ($ks | length));
              $ks[.].r[$k.p] == ($ks[.-1].r[$k.p] + $ks[.-1].r[$k.z]))
    end;

def build($s; $splits; $panes):
  (kids($s; $splits; $panes)) as $ks
  | if $ks == null or (tiled($ks; $s) | not) then null
    else ([$ks[] | .node = (if .kind == "split" then
                              build(.ref; $splits; $panes)
                            else {leaf: .ref.pane_id} end)]
          | if any(.[]; .node == null) then null
            else {axis: $s.direction, kids: .} end) end;

def firstleaf:
  if has("leaf") then .leaf else (.kids[0].node | firstleaf) end;

def lastleaf:
  if has("leaf") then .leaf else (.kids[-1].node | lastleaf) end;

def hasleaf($n; $fid):
  if ($n | has("leaf")) then $n.leaf == $fid
  else any($n.kids[]; hasleaf(.node; $fid)) end;

def parent_of($n; $fid):
  ([$n.kids[] | select(hasleaf(.node; $fid))]) as $hit
  | if ($hit | length) == 0 then null
    elif ($hit[0].node | has("leaf")) then $n
    else parent_of($hit[0].node; $fid) end;

# tiled guarantees >= 2 kids, so both branches index safely.
def partner($par; $fid; $newaxis):
  if $par == null then null
  else (($par.kids | map(hasleaf(.node; $fid)) | index(true))) as $idx
    | if $idx == null then null
      else ($par.kids[$idx].node | has("leaf")) as $direct
        | (if $direct then $newaxis else $par.axis end) as $ax
        | if $idx > 0 then
            {dir: (if $ax == "right" then "left"
                   elif $ax == "down" then "up"
                   else null end),
             pid: ($par.kids[$idx - 1].node | lastleaf)}
          else
            {dir: (if $ax == "right" then "right"
                   elif $ax == "down" then "down"
                   else null end),
             pid: ($par.kids[$idx + 1].node | firstleaf)}
          end
    end
  end;

def phase1($ks; $axis; $anchor; $ashare; $aslot; $fid):
  if ($ks | length) == 0 then []
  else ($ks[0]) as $k
    | (($k.node | firstleaf)) as $fl
    | (($ashare / $aslot)) as $r
    | [{mover: $fl, target: $anchor, split: $axis, ratio: $r,
        focus: ($fl == $fid)}]
      + phase1($ks[1:]; $axis; $fl; $k.share; ($aslot - $ashare); $fid)
  end;

def place($ms; $axis; $fid):
  phase1($ms[1:]; $axis; ($ms[0].node | firstleaf); $ms[0].share; 1; $fid)
  + ([$ms[] | select(.node | has("kids"))
       | place(.node.kids; .node.axis; $fid)] | flatten(1));

.result.layout as $layout
| $layout.panes as $panes
| ($panes | length) as $count
| (first($panes[] | select(.pane_id == $id)) // null) as $me
| if $layout.zoomed then
    {toast: "tab is zoomed"}
  elif $me == null then
    {toast: "pane not found"}
  elif $count < 2 then
    {toast: "only one pane in this tab"}
  else
    ($me.rect) as $r
    | (first($layout.splits[]? | select(boxeq(.rect; $layout.area))) // null) as $root
    | ([$layout.splits[]?
         | select(inside($r; .rect))
         | {s: ., a: (.rect.width * .rect.height)}]
        | min_by(.a).s // null) as $psplit
    | if $root == null or $psplit == null then
        {toast: "layout is not a clean split tree"}
      else
        (build($psplit; ($layout.splits // []); $panes)) as $parent
         | if $parent == null then
             {toast: "layout is not a clean split tree"}
           else
             (($parent.axis | flip)) as $newaxis
             | if $newaxis == null then
                 {toast: "layout is not a clean split tree"}
               else
                 ($parent.kids[0].node | firstleaf) as $keeper
                 | (parent_of($parent; $id)) as $par
                 | (partner($par; $id; $newaxis)) as $mate
                 | (place($parent.kids; $newaxis; $id)) as $moves
                 | {workspace: $layout.workspace_id,
                    tab: $layout.tab_id,
                    focus: (if $id != $keeper and $mate != null
                               and $mate.dir != null
                            then $mate else null end),
                    moves: $moves}
               end
           end
      end
  end
