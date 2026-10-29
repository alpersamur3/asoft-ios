// UIKit edge type for touches of a digitizer whose firmware sets no edge bits (ASoftware, iOS 26
// on QEMU: a USB HID touchscreen through AppleUserHIDEventDriver).
//
// _UITouchSetBasicTouchPropertiesFromEvent(touch = x19, ..., child event) calls
// _UIEventHIDTouchEdgeTypeForHIDEvent(event), which reads only the digitizer event mask's
// FromEdgeTip/FromCorner/SwipePending bits (0x800/0x1000/0x2000, 1<<18) that Apple's touch
// firmware sets for a contact that starts at a panel edge. Without them no touch is an edge touch:
// no home gesture, app switcher or edge swipe back. The patched call site branches here instead:
//   - the firmware's answer, where the mask has one;
//   - else at the touch-down event (mask's Touch change bit, Touch 1): 1 (FromEdgeTip) where the
//     contact starts within EDGE_X of the left or right edge or EDGE_Y of the top or bottom one
//     (normalized digitizer X/Y), else 0;
//   - else the touch's own edge type (UITouch._edgeType, at +0x20), which the touch-down set: a
//     contact keeps its edge type for its whole life, as the firmware's bits do.
// x19 is the caller's UITouch (may be nil); it is saved and restored unchanged.

    .text
    .globl cave
    .p2align 2
cave:
    pacibsp
    stp     x20, x19, [sp, #-0x30]!
    stp     d8, d9, [sp, #0x10]
    stp     x29, x30, [sp, #0x20]
    add     x29, sp, #0x20
    mov     x20, x0
    bl      orig_edge_type
    cbnz    x0, done
    mov     x0, x20
    mov     w1, #0x7
    movk    w1, #0xb, lsl #16
    bl      get_integer
    tbz     w0, #1, keep
    mov     x0, x20
    mov     w1, #0x9
    movk    w1, #0xb, lsl #16
    bl      get_integer
    cbz     x0, keep
    mov     x0, x20
    mov     w1, #0xb0000
    bl      get_float
    fmov    d8, d0
    mov     x0, x20
    mov     w1, #0x1
    movk    w1, #0xb, lsl #16
    bl      get_float
    ldr     d1, edge_x
    fcmp    d8, d1
    b.mi    edge
    ldr     d1, edge_x_hi
    fcmp    d8, d1
    b.gt    edge
    ldr     d1, edge_y
    fcmp    d0, d1
    b.mi    edge
    ldr     d1, edge_y_hi
    fcmp    d0, d1
    b.gt    edge
    mov     x0, #0
    b       done
edge:
    mov     x0, #1
    b       done
keep:
    mov     x0, #0
    cbz     x19, done
    ldr     x0, [x19, #0x20]
done:
    ldp     x29, x30, [sp, #0x20]
    ldp     d8, d9, [sp, #0x10]
    ldp     x20, x19, [sp], #0x30
    retab

    .p2align 3
edge_x:     .double 0.035
edge_x_hi:  .double 0.965
edge_y:     .double 0.02
edge_y_hi:  .double 0.98
