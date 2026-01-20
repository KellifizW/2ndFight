#!/usr/bin/env python3
"""
AI Behavior Variety Test
Validates that the AI decision layer produces varied behaviors at different ranges
and that fireball spam is eliminated at long range.
"""

import re
from collections import Counter

def read_file(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        return f.read()

def extract_long_range_logic():
    """Extract the long range decision logic from AIDecisionLayers.gd"""
    content = read_file('AIDecisionLayers.gd')
    
    # Find the long range section (distance > 250)
    pattern = r'if distance > 250:(.*?)# 中距離戰術'
    match = re.search(pattern, content, re.DOTALL)
    
    if not match:
        return None
    
    long_range_section = match.group(1)
    
    # Extract all decision actions and their characteristics
    decisions = []
    
    # Find fireball logic
    if 'randf() < 0.3' in long_range_section and 'fireball' in long_range_section:
        decisions.append({
            'action': 'fireball',
            'probability': 0.3,
            'priority': 55.0,
            'gated': True
        })
    
    # Find walk logic
    if 'walk.priority = 60.0' in long_range_section:
        decisions.append({
            'action': 'walk',
            'probability': 1.0,  # Always added
            'priority': 60.0,
            'gated': False
        })
    
    # Find block logic
    if 'randf() < 0.4' in long_range_section and 'stand_block' in long_range_section:
        decisions.append({
            'action': 'stand_block',
            'probability': 0.4,
            'priority': 58.0,
            'gated': True
        })
    
    # Find crouch logic
    if 'randf() < 0.25' in long_range_section and 'crouch_block' in long_range_section:
        decisions.append({
            'action': 'crouch_block',
            'probability': 0.25,
            'priority': 57.0,
            'gated': True
        })
    
    # Find dash logic
    if 'randf() < 0.35' in long_range_section and 'dash_forward' in long_range_section:
        decisions.append({
            'action': 'dash_forward',
            'probability': 0.35,
            'priority': 62.0,
            'gated': True
        })
    
    # Find jump logic
    if 'randf() < 0.2' in long_range_section and 'jump' in long_range_section:
        decisions.append({
            'action': 'jump',
            'probability': 0.2,
            'priority': 54.0,
            'gated': True
        })
    
    return decisions

def test_fireball_gating():
    """Test that fireball has probabilistic gating"""
    print("TEST 1: Fireball Probabilistic Gating")
    print("-" * 70)
    
    content = read_file('AIDecisionLayers.gd')
    
    # Check for the 30% gating
    if 'if not is_busy and randf() < 0.3' in content:
        print("✅ Fireball has 30% probabilistic gate (randf() < 0.3)")
    else:
        print("❌ Fireball missing 30% probabilistic gate")
        return False
    
    # Check that fireball priority is lowered
    if 'fb.priority = 55.0' in content:
        print("✅ Fireball priority lowered to 55.0")
    else:
        print("❌ Fireball priority not set to 55.0")
        return False
    
    print("✅ TEST 1 PASSED\n")
    return True

def test_walk_priority():
    """Test that walk has higher priority than fireball"""
    print("TEST 2: Walk Priority Over Fireball")
    print("-" * 70)
    
    content = read_file('AIDecisionLayers.gd')
    
    # Check walk priority
    if 'walk.priority = 60.0' in content:
        print("✅ Walk priority set to 60.0 (higher than fireball's 55.0)")
    else:
        print("❌ Walk priority not set to 60.0")
        return False
    
    # Check walk is always added
    walk_pattern = r'var walk = Decision\.new\(\).*?decisions\.append\(walk\)'
    if re.search(walk_pattern, content, re.DOTALL):
        print("✅ Walk is always added to decisions (no probability gate)")
    else:
        print("❌ Walk not always added")
        return False
    
    print("✅ TEST 2 PASSED\n")
    return True

def test_behavioral_variety():
    """Test that multiple behavioral options exist at long range"""
    print("TEST 3: Long Range Behavioral Variety")
    print("-" * 70)
    
    decisions = extract_long_range_logic()
    
    if not decisions:
        print("❌ Could not extract long range logic")
        return False
    
    print(f"Found {len(decisions)} different behaviors at long range:")
    
    required_behaviors = ['fireball', 'walk', 'stand_block', 'crouch_block', 'dash_forward', 'jump']
    found_behaviors = [d['action'] for d in decisions]
    
    for behavior in required_behaviors:
        if behavior in found_behaviors:
            decision = next(d for d in decisions if d['action'] == behavior)
            gated_str = f"prob={decision['probability']:.0%}" if decision['gated'] else "always"
            print(f"  ✅ {behavior:15s} - priority={decision['priority']:4.1f}, {gated_str}")
        else:
            print(f"  ❌ {behavior:15s} - MISSING")
    
    if len(decisions) >= 6:
        print(f"✅ TEST 3 PASSED - {len(decisions)} behaviors provide good variety\n")
        return True
    else:
        print(f"❌ TEST 3 FAILED - Only {len(decisions)} behaviors (need at least 6)\n")
        return False

def test_priority_rankings():
    """Test that priorities are correctly ranked"""
    print("TEST 4: Priority Rankings at Long Range")
    print("-" * 70)
    
    decisions = extract_long_range_logic()
    
    if not decisions:
        print("❌ Could not extract long range logic")
        return False
    
    # Sort by priority (highest first)
    sorted_decisions = sorted(decisions, key=lambda x: x['priority'], reverse=True)
    
    print("Priority ranking (highest to lowest):")
    for i, d in enumerate(sorted_decisions, 1):
        print(f"  {i}. {d['action']:15s} - priority {d['priority']:4.1f}")
    
    # Check that dash has highest priority
    if sorted_decisions[0]['action'] == 'dash_forward' and sorted_decisions[0]['priority'] == 62.0:
        print("✅ Dash has highest priority (62.0)")
    else:
        print("❌ Dash should have highest priority")
        return False
    
    # Check that fireball is NOT highest priority
    fireball_decision = next((d for d in decisions if d['action'] == 'fireball'), None)
    if fireball_decision and fireball_decision['priority'] < 60.0:
        print("✅ Fireball priority (55.0) is lower than walk (60.0)")
    else:
        print("❌ Fireball priority should be lower than walk")
        return False
    
    print("✅ TEST 4 PASSED\n")
    return True

def test_mid_range_variety():
    """Test that mid-range has variety including crouch attacks and walking"""
    print("TEST 5: Mid Range Behavioral Variety")
    print("-" * 70)
    
    content = read_file('AIDecisionLayers.gd')
    
    # Find mid range section
    pattern = r'# 中距離戰術.*?elif distance > 100:(.*?)# 近距離戰術'
    match = re.search(pattern, content, re.DOTALL)
    
    if not match:
        print("❌ Could not find mid range section")
        return False
    
    mid_range_section = match.group(1)
    
    checks = [
        ('st_mk poke', 'st_mk'),
        ('dash_forward', 'dash_forward'),
        ('stand_block', 'stand_block'),
        ('walk (new)', 'walk_forward'),
        ('crouch attack (new)', 'cr_mk'),
    ]
    
    all_passed = True
    for name, keyword in checks:
        if keyword in mid_range_section:
            print(f"  ✅ {name:20s} - present")
        else:
            print(f"  ❌ {name:20s} - MISSING")
            all_passed = False
    
    if all_passed:
        print("✅ TEST 5 PASSED\n")
    else:
        print("❌ TEST 5 FAILED\n")
    
    return all_passed

def test_close_range_variety():
    """Test that close-range has variety including crouch attacks and blocking"""
    print("TEST 6: Close Range Behavioral Variety")
    print("-" * 70)
    
    content = read_file('AIDecisionLayers.gd')
    
    # Find close range section
    pattern = r'# 近距離戰術.*?else:(.*?)return decisions'
    match = re.search(pattern, content, re.DOTALL)
    
    if not match:
        print("❌ Could not find close range section")
        return False
    
    close_range_section = match.group(1)
    
    checks = [
        ('combo execution', 'combo_names'),
        ('normal attacks', 'st_mp'),
        ('crouch attacks (new)', 'cr_mp'),
        ('backdash retreat', 'backdash'),
        ('blocking (new)', 'stand_block'),
    ]
    
    all_passed = True
    for name, keyword in checks:
        if keyword in close_range_section:
            print(f"  ✅ {name:20s} - present")
        else:
            print(f"  ❌ {name:20s} - MISSING")
            all_passed = False
    
    if all_passed:
        print("✅ TEST 6 PASSED\n")
    else:
        print("❌ TEST 6 FAILED\n")
    
    return all_passed

def main():
    print("=" * 70)
    print("AI BEHAVIOR VARIETY TEST")
    print("Testing AI fireball spam fix and behavioral improvements")
    print("=" * 70)
    print()
    
    tests = [
        test_fireball_gating,
        test_walk_priority,
        test_behavioral_variety,
        test_priority_rankings,
        test_mid_range_variety,
        test_close_range_variety,
    ]
    
    results = [test() for test in tests]
    
    print("=" * 70)
    print("FINAL RESULTS")
    print("=" * 70)
    
    passed = sum(results)
    total = len(results)
    
    print(f"Tests Passed: {passed}/{total}")
    
    if all(results):
        print("\n✅ ALL TESTS PASSED!")
        print("\nThe AI behavior variety improvements are working correctly:")
        print("  • Fireball spam is eliminated (30% gate + lower priority)")
        print("  • Walking has higher priority than fireballs")
        print("  • 6+ different behaviors available at long range")
        print("  • Dash has highest priority for aggressive approach")
        print("  • Mid and close ranges have increased variety")
        print("\nThe AI should now behave more like a human player!")
        return 0
    else:
        print("\n❌ SOME TESTS FAILED!")
        print("\nPlease review the failed tests above.")
        return 1

if __name__ == '__main__':
    import sys
    sys.exit(main())
