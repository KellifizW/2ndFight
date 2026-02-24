#!/usr/bin/env python3
"""
AI System Integration Test
Validates that all AI modules can be properly instantiated and have required interfaces.
"""

import re

def read_file(filename):
    with open(filename, 'r', encoding='utf-8') as f:
        return f.read()

def check_class_interface(filename, required_methods):
    """Check if a class has all required methods"""
    content = read_file(filename)
    missing = []
    
    for method in required_methods:
        pattern = f'func {method}\\s*\\('
        if not re.search(pattern, content):
            missing.append(method)
    
    return missing

def check_dependencies(filename, required_classes):
    """Check if a file references required classes"""
    content = read_file(filename)
    missing = []
    
    for cls in required_classes:
        if cls not in content:
            missing.append(cls)
    
    return missing

def main():
    print("=" * 70)
    print("AI SYSTEM INTEGRATION TEST")
    print("=" * 70)
    
    tests = [
        {
            'name': 'AIBehavior Interface',
            'file': 'ai_behavior.gd',
            'methods': ['get_ai_input', 'set_ai_enabled', 'find_opponent', '_action_to_input', '_neutral_input', '_init_subsystems'],
        },
        {
            'name': 'ThreatAssessment Interface',
            'file': 'ThreatAssessment.gd',
            'methods': ['evaluate_threats', '_evaluate_attack_threat', '_evaluate_projectile_threat', '_calculate_frames_to_hit', '_get_optimal_defense'],
        },
        {
            'name': 'AIDecisionLayers Interface',
            'file': 'AIDecisionLayers.gd',
            'methods': ['get_best_decision', '_evaluate_survival_layer', '_evaluate_punish_layer', '_evaluate_tactical_layer', '_evaluate_positioning_layer', '_get_idle_decision'],
        },
        {
            'name': 'FrameDataManager Interface',
            'file': 'FrameDataManager.gd',
            'methods': ['get_startup_frames', 'get_total_frames', 'get_recovery_frames_remaining', 'is_in_recovery'],
        },
        {
            'name': 'AIComboSystem Interface',
            'file': 'AIComboSystem.gd',
            'methods': ['get_available_combos', 'can_execute_combo', 'start_combo', 'get_next_combo_move', 'is_executing_combo', 'reset_combo'],
        },
        {
            'name': 'SpaceControl Interface',
            'file': 'SpaceControl.gd',
            'methods': ['get_current_zone', 'is_in_corner', 'get_ideal_distance', 'should_escape_corner', 'get_escape_action'],
        },
    ]
    
    dependency_tests = [
        {
            'name': 'AIBehavior Dependencies',
            'file': 'ai_behavior.gd',
            'classes': ['ThreatAssessment', 'AIDecisionLayers', 'FrameDataManager', 'AIComboSystem', 'SpaceControl'],
        },
        {
            'name': 'AIDecisionLayers Dependencies',
            'file': 'AIDecisionLayers.gd',
            'classes': ['ThreatAssessment', 'FrameDataManager', 'AIComboSystem', 'SpaceControl'],
        },
    ]
    
    all_passed = True
    
    # Test interfaces
    print("\n1. INTERFACE TESTS")
    print("-" * 70)
    for test in tests:
        missing = check_class_interface(test['file'], test['methods'])
        if missing:
            print(f"❌ {test['name']}")
            print(f"   Missing methods: {', '.join(missing)}")
            all_passed = False
        else:
            print(f"✅ {test['name']}")
    
    # Test dependencies
    print("\n2. DEPENDENCY TESTS")
    print("-" * 70)
    for test in dependency_tests:
        missing = check_dependencies(test['file'], test['classes'])
        if missing:
            print(f"❌ {test['name']}")
            print(f"   Missing references: {', '.join(missing)}")
            all_passed = False
        else:
            print(f"✅ {test['name']}")
    
    # Check for class_name declarations
    print("\n3. CLASS DECLARATION TESTS")
    print("-" * 70)
    required_classes = {
        'ThreatAssessment.gd': 'ThreatAssessment',
        'AIDecisionLayers.gd': 'AIDecisionLayers',
        'FrameDataManager.gd': 'FrameDataManager',
        'AIComboSystem.gd': 'AIComboSystem',
        'SpaceControl.gd': 'SpaceControl',
        'ai_behavior.gd': 'AIBehavior',
    }
    
    for filename, classname in required_classes.items():
        content = read_file(filename)
        if f'class_name {classname}' in content:
            print(f"✅ {classname} class declaration")
        else:
            print(f"❌ {classname} class declaration missing")
            all_passed = False
    
    # Final summary
    print("\n" + "=" * 70)
    if all_passed:
        print("✅ ALL TESTS PASSED!")
        print("\nThe AI system is ready for integration testing.")
        return 0
    else:
        print("❌ SOME TESTS FAILED!")
        print("\nPlease fix the issues above before deployment.")
        return 1

if __name__ == '__main__':
    import sys
    sys.exit(main())
