export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/resumo`);
  const data = await res.json();

  const container = document.getElementById("tab-resumo");
  container.innerHTML = `
    <div class="resume-sections">
      <div class="resume-item"><strong>Última avaliação:</strong> ${data.ultima_avaliacao || "-"}</div>
      <div class="resume-item"><strong>Score Corporal:</strong> ${data.score || "-"}</div>
      <div class="resume-item"><strong>Peso atual:</strong> ${data.peso || "-"} kg</div>
    </div>
  `;
}
