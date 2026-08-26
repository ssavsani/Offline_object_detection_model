"""Inspect the RF-DETR Nano ONNX model: inputs, outputs, ops used.

Run: python3 python/inspect_model.py
"""
import onnx
import onnxruntime as ort
import os

MODEL_PATH = os.path.join(os.path.dirname(__file__), "..", "rfdetr-nano.onnx")


def main():
    print("=" * 60)
    print("Loading with onnx.load() for static graph info")
    print("=" * 60)
    model = onnx.load(MODEL_PATH)
    onnx.checker.check_model(model)
    print(f"IR version: {model.ir_version}")
    print(f"Opset: {[op.version for op in model.opset_import]}")

    print("\n--- Graph Inputs ---")
    for inp in model.graph.input:
        dims = [d.dim_value if d.dim_value else d.dim_param for d in inp.type.tensor_type.shape.dim]
        print(f"  name={inp.name} dtype={inp.type.tensor_type.elem_type} shape={dims}")

    print("\n--- Graph Outputs ---")
    for out in model.graph.output:
        dims = [d.dim_value if d.dim_value else d.dim_param for d in out.type.tensor_type.shape.dim]
        print(f"  name={out.name} dtype={out.type.tensor_type.elem_type} shape={dims}")

    op_types = {}
    for node in model.graph.node:
        op_types[node.op_type] = op_types.get(node.op_type, 0) + 1
    print("\n--- Op type histogram (top 30) ---")
    for op, cnt in sorted(op_types.items(), key=lambda x: -x[1])[:30]:
        print(f"  {op}: {cnt}")
    print(f"\nTotal nodes: {len(model.graph.node)}")
    has_sigmoid = "Sigmoid" in op_types
    has_softmax = "Softmax" in op_types
    print(f"\nContains Sigmoid op in graph: {has_sigmoid}")
    print(f"Contains Softmax op in graph: {has_softmax}")

    print("\n" + "=" * 60)
    print("Loading with onnxruntime.InferenceSession")
    print("=" * 60)
    sess = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
    print("\n--- Session Inputs ---")
    for i in sess.get_inputs():
        print(f"  name={i.name} shape={i.shape} type={i.type}")
    print("\n--- Session Outputs ---")
    for o in sess.get_outputs():
        print(f"  name={o.name} shape={o.shape} type={o.type}")


if __name__ == "__main__":
    main()
