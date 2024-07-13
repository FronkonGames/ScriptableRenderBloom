using UnityEngine;

namespace FronkonGames.Glitches.JPEG
{
  /// <summary> Simple object rotation. </summary>
  /// <remarks> This code is designed for a simple demo, not for production environments. </remarks>
  public sealed class Rotate : MonoBehaviour
  {
    [SerializeField]
    private Vector3 angularSpeed = new(0.0f, 15.0f, 0.0f);

    private void Update() => transform.Rotate(angularSpeed * Time.deltaTime);
  }
}