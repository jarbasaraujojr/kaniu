export async function load(animalId) {
  const res = await fetch(`/api/animals/${animalId}/imunizacoes`);
  const data = await res.json();

  const container = document.getElementById("tab-imunizacoes");
  if (!data.length) {
    container.innerHTML = "<p>Nenhuma imunização encontrada.</p>";
    return;
  }

  container.innerHTML = `
    <table class="tab-table">
      <thead>
        <tr><th>Data</th><th>Tipo</th><th>Imunizante</th><th>Veterinário</th><th>Aplicada</th></tr>
      </thead>
      <tbody>
        ${data.map(im => `
          <tr>
            <td>${im.data_exibicao}</td>
            <td>${im.tipo}</td>
            <td>${im.nome_imunizante}</td>
            <td>${im.veterinario_nome || "-"}</td>
            <td>${im.aplicada ? "Sim" : "Não"}</td>
          </tr>
        `).join("")}
      </tbody>
    </table>
  `;
}
