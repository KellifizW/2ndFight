# Compile Prompt for Optimizing `ai_behavior.gd`

## Objective
Optimize the `ai_behavior.gd` script for a 2D fighting game in Godot 4.5, based on the specifications in `ai_behavior_spec.md`. The goal is to improve modularity, performance, and decision-making while maintaining existing functionality and ensuring compatibility with Godot 4.5.

## Instructions for AI or Developer
Use this prompt in VS Code with an AI coding assistant (e.g., GitHub Copilot) or manually to guide the optimization of `ai_behavior.gd`. Follow these steps:

1. **Read the Specification**:
   - Load `ai_behavior_spec.md` to understand the script’s functionality, improvement goals, and constraints.
   - Ensure all changes align with the specified goals (e.g., modularization, smarter AI, Godot 4.5 compatibility).

2. **Analyze Current Code**:
   - Review `ai_behavior.gd` for areas of improvement, focusing on:
     - Monolithic functions (`update_ai_state`, `get_ai_input`).
     - Redundant node access (e.g., repeated `get_node` calls).
     - Overuse of debug prints in non-debug builds.
     - Lack of null checks for `parent` and `opponent`.

3. **Propose Changes**:
   - **Modularization**:
     - Split `update_ai_state` into smaller functions (e.g., `handle_idle_state`, `handle_attack_state`) for each state.
     - Create a dedicated `StateMachine` class or dictionary to manage state transitions.
   - **Performance**:
     - Cache nodes like `Hitbox`, `Hurtbox`, and `healthbar` in `_ready()`.
     - Wrap debug prints in `if OS.is_debug_build()` to reduce overhead.
   - **Decision-Making**:
     - Implement a priority system for actions (e.g., prioritize special moves when `opponent_stun_remaining > 0.15`).
     - Add adaptive difficulty by scaling probabilities based on player health or match time.
   - **Error Handling**:
     - Add null checks for `parent`, `opponent`, and their properties (e.g., `healthbar`, `Hitbox`).
     - Validate `Area2D` overlap checks to prevent crashes.
   - **Godot 4.5 Compatibility**:
     - Verify properties like `is_jumping`, `is_attacking`, and `attack_timer` match Godot 4.5’s API.
     - Use Godot 4.5’s `Area2D` signals for overlap detection if applicable.

4. **Apply Changes**:
   - Use VS Code’s Godot Tools extension to edit `ai_behavior.gd`.
   - Preserve existing functionality unless explicitly improving it (e.g., maintain state logic but refactor for clarity).
   - Ensure all declarations (e.g., `@onready var parent: Node`) remain correct and compatible with inheritance.

5. **Test Changes**:
   - Run the game in Godot 4.5 to verify AI behavior (e.g., smooth state transitions, no crashes).
   - Use a test scene to simulate AI vs. player or AI vs. AI scenarios.
   - Check debug output (in debug builds) to confirm state changes, timers, and input decisions.

6. **Document Changes**:
   - Add comments explaining new functions or logic changes.
   - Update `ai_behavior_spec.md` if new features or behaviors are introduced.

## Constraints
- **Godot 4.5 Only**: Ensure all code uses Godot 4.5 APIs and avoids deprecated features.
- **No File I/O**: Do not add file operations, as the script runs in a game environment.
- **File Integrity**: Retain all existing functionality unless explicitly modified. Do not delete working code without justification.
- **Debugging**: Minimize debug output in non-debug builds using `OS.is_debug_build()`.

## Success Criteria
- The optimized `ai_behavior.gd` should:
  - Be more modular and readable (e.g., smaller functions, clear state machine).
  - Run without errors in Godot 4.5.
  - Exhibit smarter AI behavior (e.g., better counterattacks, adaptive difficulty).
  - Maintain or improve performance (e.g., fewer node lookups, optimized debug output).
- The AI should feel challenging but fair, with smooth state transitions and no abrupt behavior changes.

## Example Workflow in VS Code
1. Open `ai_behavior.gd` in VS Code with the Godot Tools extension.
2. Use the AI assistant to suggest refactored code based on this prompt.
3. Apply changes incrementally, testing each change in Godot 4.5.
4. Use `ai_behavior_spec.md` to validate that all improvement goals are met.
5. Run the game and observe AI behavior in a test scene.

## Resources
- **Godot 4.5 Documentation**: [https://docs.godotengine.org/en/stable/](https://docs.godotengine.org/en/stable/)
- **VS Code Godot Tools**: Install via VS Code Marketplace for GDScript syntax checking.
- **Original Code**: Refer to `ai_behavior.gd` for the current implementation.