#!/usr/bin/env python3
"""
Test suite for motion input detection in 2ndFight.
Parses actual .tres files and tests motion recognition against fighting game input patterns.
"""

import os
import re

class DirectionalInputs:
    NEUTRAL = 0
    DOWN = 1
    DOWN_FORWARD = 2
    FORWARD = 3
    DOWN_BACK = 4
    BACK = 5
    UP = 6
    UP_FORWARD = 7
    UP_BACK = 8

class ButtonInputs:
    NONE = 0
    ST_LP = 1
    ST_MP = 2
    ST_HP = 4
    ST_LK = 8
    ST_MK = 16
    ST_HK = 32

_MIRROR_DIR = {2: 4, 3: 5, 4: 2, 5: 3, 7: 8, 8: 7}

class InputRegistry:
    def __init__(self, raw_input=0, duration=1):
        self.raw_input = raw_input
        self.duration = duration

class InputManagerSim:
    def __init__(self, facing=1.0, input_buffer=30, max_total_frames=120):
        self.INPUT_HISTORY_SIZE = 240
        self.INPUT_BUFFER = input_buffer
        self.MAX_TOTAL_FRAMES = max_total_frames
        self.facing_direction = facing
        self.input_history = [InputRegistry() for _ in range(self.INPUT_HISTORY_SIZE)]
        self.current_history = 0

    def get_relative_direction(self, absolute_dir: int) -> int:
        if self.facing_direction >= 0:
            return absolute_dir
        return _MIRROR_DIR.get(absolute_dir, absolute_dir)

    def insert_input(self, dir_val: int, buttons: int, duration_frames: int = 1):
        raw_input = (dir_val << 8) | buttons
        for _ in range(duration_frames):
            curr = self.input_history[self.current_history]
            if curr.raw_input != raw_input:
                self.current_history = (self.current_history + 1) % self.INPUT_HISTORY_SIZE
                self.input_history[self.current_history] = InputRegistry(raw_input, 1)
            else:
                curr.duration += 1

    def check_input(self, index: int, directional: int, buttons: int, absolute_direction: bool = False) -> bool:
        raw = self.input_history[index].raw_input
        absolute_dir = raw >> 8
        input_buttons = raw & 0xFF
        relative_dir = self.get_relative_direction(absolute_dir)
        dir_match = (directional == absolute_dir) if absolute_direction else (directional == relative_dir)
        but_match = (buttons == ButtonInputs.NONE) or ((input_buttons & buttons) != 0)
        return dir_match and but_match

    def check_motion(self, motion: dict) -> bool:
        if not motion:
            return False
        input_buffer_size = motion.get("InputBuffer", self.INPUT_BUFFER)
        max_total_frames = motion.get("MaxTotalFrames", self.MAX_TOTAL_FRAMES)
        absolute_direction = motion.get("AbsoluteDirection", False)
        valid_inputs = motion.get("ValidInputs", [])
        
        current_buttons = self.input_history[self.current_history].raw_input & 0xFF
        current_duration = self.input_history[self.current_history].duration
        if current_duration > input_buffer_size:
            return False

        for seq in valid_inputs:
            if not seq:
                continue
            target_button = seq[-1].get("buttons", ButtonInputs.NONE)
            if target_button != ButtonInputs.NONE:
                if (current_buttons & target_button) == 0:
                    continue
            
            seq_idx = len(seq) - 1
            hist_pos = self.current_history
            total_frames = 0
            matched = True
            
            while seq_idx >= 0 and matched:
                step = seq[seq_idx]
                is_final_step = (seq_idx == len(seq) - 1)
                step_matched = False
                step_frames = 0
                required_dir = step.get("directional", DirectionalInputs.NEUTRAL)
                required_btn = ButtonInputs.NONE if is_final_step else step.get("buttons", ButtonInputs.NONE)
                
                if is_final_step:
                    if required_dir == DirectionalInputs.NEUTRAL:
                        step_matched = True
                        seq_idx -= 1
                    else:
                        while hist_pos >= 0 and not step_matched and step_frames < input_buffer_size:
                            hist = self.input_history[hist_pos]
                            step_frames += hist.duration
                            total_frames += hist.duration
                            if total_frames > max_total_frames:
                                matched = False
                                break
                            if self.check_input(hist_pos, required_dir, ButtonInputs.NONE, absolute_direction):
                                step_matched = True
                                seq_idx -= 1
                            hist_pos = (hist_pos - 1 + self.INPUT_HISTORY_SIZE) % self.INPUT_HISTORY_SIZE
                else:
                    while hist_pos >= 0 and not step_matched and step_frames < input_buffer_size:
                        hist = self.input_history[hist_pos]
                        step_frames += hist.duration
                        total_frames += hist.duration
                        if total_frames > max_total_frames:
                            matched = False
                            break
                        if self.check_input(hist_pos, required_dir, required_btn, absolute_direction):
                            step_matched = True
                            seq_idx -= 1
                        hist_pos = (hist_pos - 1 + self.INPUT_HISTORY_SIZE) % self.INPUT_HISTORY_SIZE

                if not step_matched:
                    matched = False
            
            if matched:
                return True
        return False


def parse_tres_file(filepath: str) -> dict:
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    input_buffer_match = re.search(r"input_buffer\s*=\s*(\d+)", content)
    input_buffer = int(input_buffer_match.group(1)) if input_buffer_match else 30

    max_frames_match = re.search(r"max_total_frames\s*=\s*(\d+)", content)
    max_total_frames = int(max_frames_match.group(1)) if max_frames_match else 120

    seq_id_match = re.search(r'sequence_id\s*=\s*"([^"]+)"', content)
    sequence_id = seq_id_match.group(1) if seq_id_match else ""

    # Parse valid_inputs array
    # Split by inner arrays [[{...}], [{...}]]
    valid_inputs_match = re.search(r"valid_inputs\s*=\s*(\[.*\])\s*$", content, re.DOTALL)
    valid_inputs = []
    if valid_inputs_match:
        # Evaluate valid_inputs JSON-like structure
        raw_str = valid_inputs_match.group(1)
        # Parse steps using regex
        seq_blocks = re.findall(r"\[\s*(\{.*?\})\s*\]", raw_str, re.DOTALL)
        for block in seq_blocks:
            step_dicts = []
            steps = re.findall(r"\{([^}]+)\}", block)
            for st in steps:
                d_match = re.search(r'"directional":\s*(\d+)', st)
                b_match = re.search(r'"buttons":\s*(\d+)', st)
                step_dicts.append({
                    "directional": int(d_match.group(1)) if d_match else 0,
                    "buttons": int(b_match.group(1)) if b_match else 0
                })
            if step_dicts:
                valid_inputs.append(step_dicts)

    return {
        "sequence_id": sequence_id,
        "InputBuffer": input_buffer,
        "MaxTotalFrames": max_total_frames,
        "ValidInputs": valid_inputs
    }


def run_all_tests():
    base_dir = os.path.dirname(os.path.abspath(__file__))
    inputs_dir = os.path.join(base_dir, "..", "data", "specials", "inputs")

    dp_data = parse_tres_file(os.path.join(inputs_dir, "dp_input.tres"))
    fb_data = parse_tres_file(os.path.join(inputs_dir, "fireball_input.tres"))
    p100_data = parse_tres_file(os.path.join(inputs_dir, "100p_input.tres"))
    hdk_data = parse_tres_file(os.path.join(inputs_dir, "hdk_input.tres"))
    powerkk_data = parse_tres_file(os.path.join(inputs_dir, "powerkk_input.tres"))
    spnk_data = parse_tres_file(os.path.join(inputs_dir, "spnk_input.tres"))

    print(f"Loaded DP sequences: {len(dp_data['ValidInputs'])}, buffer={dp_data['InputBuffer']}")
    print(f"Loaded Fireball sequences: {len(fb_data['ValidInputs'])}, buffer={fb_data['InputBuffer']}")
    print(f"Loaded 100p sequences: {len(p100_data['ValidInputs'])}, buffer={p100_data['InputBuffer']}")
    print(f"Loaded HDK sequences: {len(hdk_data['ValidInputs'])}, buffer={hdk_data['InputBuffer']}")
    print(f"Loaded PowerKK sequences: {len(powerkk_data['ValidInputs'])}, buffer={powerkk_data['InputBuffer']}")
    print(f"Loaded SPNK sequences: {len(spnk_data['ValidInputs'])}, buffer={spnk_data['InputBuffer']}")

    assert len(dp_data['ValidInputs']) >= 9, "DP should have comprehensive valid inputs"
    assert len(fb_data['ValidInputs']) >= 5, "Fireball should have valid inputs"

    D = DirectionalInputs
    B = ButtonInputs

    # -------------------------------------------------------------
    # TEST SUITE 1: DP Input Detection & Priority
    # -------------------------------------------------------------
    # 1.1 Standard 6236+MP (DP roll ending forward)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.FORWARD, B.ST_MP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "6236+MP must detect DP"
    print("✅ 1.1 Standard 6236+MP -> DP detected")

    # 1.2 Standard 623+MP (DP ending on down-forward)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.ST_MP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "623+MP must detect DP"
    print("✅ 1.2 Standard 623+MP -> DP detected")

    # 1.3 Arcade stick roll 63236+HP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.FORWARD, B.ST_HP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "63236+HP must detect DP"
    print("✅ 1.3 Arcade stick roll 63236+HP -> DP detected")

    # 1.4 Crouch DP shortcut 323+LP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN_FORWARD, B.ST_LP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "323+LP must detect DP"
    print("✅ 1.4 Crouch DP 323+LP -> DP detected")

    # 1.5 Dirty DP 626+MP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=6)
    sim.insert_input(D.FORWARD, B.ST_MP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "626+MP must detect DP"
    print("✅ 1.5 Dirty DP 626+MP -> DP detected")

    # 1.6 Facing Left (P2) 6236+MP
    sim = InputManagerSim(facing=-1.0)
    sim.insert_input(D.BACK, B.NONE, duration_frames=8)        # Physical Left = Relative Forward
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)        # Physical Down = Relative Down
    sim.insert_input(D.DOWN_BACK, B.NONE, duration_frames=8)   # Physical Down-Left = Relative Down-Forward
    sim.insert_input(D.BACK, B.ST_MP, duration_frames=2)       # Physical Left = Relative Forward + MP
    assert sim.check_motion(dp_data) == True, "Facing Left 6236+MP must detect DP"
    print("✅ 1.6 Facing Left 6236+MP -> DP detected")

    # -------------------------------------------------------------
    # TEST SUITE 2: Fireball (236) Input Detection
    # -------------------------------------------------------------
    # 2.1 Standard 236+LP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.FORWARD, B.ST_LP, duration_frames=2)
    assert sim.check_motion(fb_data) == True, "236+LP must detect Fireball"
    assert sim.check_motion(dp_data) == False, "Pure 236+LP must NOT match DP"
    print("✅ 2.1 Standard 236+LP -> Fireball detected, DP not matched")

    # 2.2 Standard 236+MP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.FORWARD, B.ST_MP, duration_frames=2)
    assert sim.check_motion(fb_data) == True, "236+MP must detect Fireball"
    assert sim.check_motion(dp_data) == False, "Pure 236+MP must NOT match DP"
    print("✅ 2.2 Standard 236+MP -> Fireball detected, DP not matched")

    # 2.3 Dirty start 1236+HP
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN_BACK, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.FORWARD, B.ST_HP, duration_frames=2)
    assert sim.check_motion(fb_data) == True, "1236+HP must detect Fireball"
    print("✅ 2.3 Dirty start 1236+HP -> Fireball detected")

    # 2.4 Facing Left (P2) 236+MP
    sim = InputManagerSim(facing=-1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_BACK, B.NONE, duration_frames=8)
    sim.insert_input(D.BACK, B.ST_MP, duration_frames=2)
    assert sim.check_motion(fb_data) == True, "Facing Left 236+MP must detect Fireball"
    assert sim.check_motion(dp_data) == False, "Facing Left 236+MP must NOT match DP"
    print("✅ 2.4 Facing Left 236+MP -> Fireball detected")

    # -------------------------------------------------------------
    # TEST SUITE 3: Other Specials (100p, HDK, PowerKK, SPNK)
    # -------------------------------------------------------------
    # 3.1 100p (236+MK for DAV)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.FORWARD, B.ST_MK, duration_frames=2)
    assert sim.check_motion(p100_data) == True, "236+MK must detect 100p"
    print("✅ 3.1 236+MK -> 100p detected")

    # 3.2 HDK (236+MK for DEN)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=8)
    sim.insert_input(D.FORWARD, B.ST_MK, duration_frames=2)
    assert sim.check_motion(hdk_data) == True, "236+MK must detect HDK"
    print("✅ 3.2 236+MK -> HDK detected")

    # 3.3 PowerKK (214+MP for DAV)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_BACK, B.NONE, duration_frames=8)
    sim.insert_input(D.BACK, B.ST_MP, duration_frames=2)
    assert sim.check_motion(powerkk_data) == True, "214+MP must detect PowerKK"
    print("✅ 3.3 214+MP -> PowerKK detected")

    # 3.4 SPNK (214+MK for DEN)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=8)
    sim.insert_input(D.DOWN_BACK, B.NONE, duration_frames=8)
    sim.insert_input(D.BACK, B.ST_MK, duration_frames=2)
    assert sim.check_motion(spnk_data) == True, "214+MK must detect SPNK"
    print("✅ 3.4 214+MK -> SPNK detected")

    # -------------------------------------------------------------
    # TEST SUITE 4: Human Execution Leniency & Edge Cases
    # -------------------------------------------------------------
    # 4.1 Slow Human Execution (15-20 frames per step @ 120 FPS)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=18)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=16)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=14)
    sim.insert_input(D.FORWARD, B.ST_MP, duration_frames=3)
    assert sim.check_motion(dp_data) == True, "Slow 18F-step DP must succeed"
    print("✅ 4.1 Slow human execution (18F steps) -> DP detected")

    # 4.2 Multi-button Plinking / Overlap (LP+MP together)
    sim = InputManagerSim(facing=1.0)
    sim.insert_input(D.FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN, B.NONE, duration_frames=6)
    sim.insert_input(D.DOWN_FORWARD, B.NONE, duration_frames=6)
    sim.insert_input(D.FORWARD, B.ST_MP | B.ST_LP, duration_frames=2)
    assert sim.check_motion(dp_data) == True, "Multi-button DP must succeed"
    print("✅ 4.2 Multi-button overlap (LP+MP) -> DP detected")

    print("\n=======================================================")
    print("🎉 ALL 14 MOTION DETECTION TESTS PASSED SUCCESSFULLY! 🎉")
    print("=======================================================")


if __name__ == "__main__":
    run_all_tests()
